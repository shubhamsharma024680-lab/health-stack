import hashlib
import secrets
import mysql.connector

from backend.transactions.server import getDBconnection
from backend.transactions.middleware import getCurrentUser
from backend.transactions.helpers import verifyPassword, hashPassword

from fastapi import Depends, HTTPException, APIRouter

router = APIRouter(prefix="/auth")


# Read-only: the display fields the frontend needs for the signed-in account.
# Patients are named from Patient; doctors and pharmacists from Employee.
def accountProfile(cur, accountId, role, userId):
    if role == "patient":
        cur.execute("SELECT First_name, Last_name, Mail FROM Patient WHERE Patient_id = %s", (userId,))
    else:
        cur.execute("SELECT First_name, Last_name, Mail FROM Employee WHERE Employee_id = %s", (userId,))
    rows = cur.fetchall()
    person = rows[0] if rows else {"First_name": "", "Last_name": "", "Mail": None}
    name = f"{person['First_name']} {person['Last_name']}".strip()
    return {"accountId": accountId, "role": role, "userId": userId, "name": name, "email": person["Mail"]}


@router.get("/me")
def me(user: dict = Depends(getCurrentUser)):
    con = getDBconnection()
    cur = con.cursor(dictionary=True)
    try:
        return accountProfile(cur, user["accountId"], user["role"], user["userId"])
    finally:
        cur.close()
        con.close()

@router.post("/login")
def login(data: dict):
    con = getDBconnection()
    cur = con.cursor(dictionary=True)
    try:
        cur.execute("START TRANSACTION")
        query = "SELECT Account_id, Password_hash, Role, User_id FROM AuthAccount WHERE Email = %s AND Role = %s"
        cur.execute(query, (data["email"], data["role"]))
        rows = cur.fetchall()
        if not rows:
            raise HTTPException(status_code=401, detail="Not registered.")
        
        userRow = rows[0]
        if not verifyPassword(data["password"], userRow['Password_hash']):
            raise HTTPException(status_code=401, detail="Incorrect Password.")
        token = secrets.token_urlsafe(32)
        t_hash = hashlib.sha256(token.encode()).hexdigest()
        
        insert_query = """
            INSERT INTO AuthSession (Token_hash, Account_id, Expires_at) 
            VALUES (%s, %s, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY))
            """
        cur.execute(insert_query, (t_hash, userRow['Account_id']))
        con.commit()
        # Return the same profile shape as /auth/me; never return Password_hash.
        user = accountProfile(cur, userRow['Account_id'], userRow['Role'], userRow['User_id'])
        return { "token": token, "user": user}
    
    except HTTPException:
        con.rollback()
        raise
    except mysql.connector.IntegrityError as exc:
        con.rollback()
        raise HTTPException( status_code=409, detail="The operation conflicts with existing database data.")
    finally:
        cur.close()
        con.close()
            
@router.post("/register")
def register(data: dict):
    con = getDBconnection()
    cur = con.cursor(dictionary=True)
    try:
        cur.execute("START TRANSACTION")
        cur.execute("SELECT Patient_id FROM Patient WHERE Mail=%s", (data["email"],))
        existingPatient = cur.fetchall()
        if existingPatient:
            raise HTTPException(status_code=403, detail="Already Registered")

        Name = data["name"].split(maxsplit=1)
        if len(Name) > 1:
            first, last = Name[0], Name[1]
        else:
            first, last = '', ''

        query = "INSERT INTO Patient (First_name,Last_name,Mail,Contact,DOB,Gender) VALUES (%s,%s,%s,%s,%s,%s)"
        cur.execute(query, (first, last, data["email"], data["phone"].removeprefix('+91'), data["dob"], data["gender"]))
        
        patient_id = cur.lastrowid
        query = "INSERT INTO AuthAccount (Email,Password_hash,Role,User_id) VALUES (%s,%s,'patient',%s)"
        cur.execute(query, (data["email"], hashPassword(data["password"]), patient_id))

        account_id = cur.lastrowid
        token = secrets.token_urlsafe(32)
        t_hash = hashlib.sha256(token.encode()).hexdigest()
        cur.execute("INSERT INTO AuthSession (Token_hash,Account_id,Expires_at) VALUES (%s,%s,DATE_ADD(UTC_TIMESTAMP(), INTERVAL 1 DAY))", (t_hash, account_id))

        con.commit()
        return {'token' : token}
    except HTTPException:
        con.rollback()
        raise
    except mysql.connector.Error as exc:
        # Undo the patient, account and session together, then explain what failed.
        con.rollback()
        if exc.errno == 1062:
            # Another request registered this email first (AuthAccount.Email is UNIQUE).
            raise HTTPException(status_code=403, detail="Already Registered") from exc
        if exc.sqlstate == '45000':
            # A trigger rejected the data, e.g. trg_patient_dob_bi for a future date of birth.
            raise HTTPException(status_code=409, detail=exc.msg) from exc
        raise HTTPException(status_code=500, detail="Could not create the account.") from exc
    finally:
        cur.close()
        con.close()

@router.delete("/session", status_code=204)
def logout(data: dict):
    token = data.get("token")
    if not isinstance(token, str) or not token:
        raise HTTPException(status_code=401, detail="Please log in.")

    token_hash = hashlib.sha256(token.encode()).hexdigest()
    con = getDBconnection()
    cur = con.cursor(dictionary=True)
    try:
        query = "DELETE FROM AuthSession WHERE Token_hash = %s"
        cur.execute(query, (token_hash,))
        con.commit()
    except mysql.connector.Error:
        con.rollback()
        raise HTTPException(status_code=500, detail="Could not log out.")
    finally:
        cur.close()
        con.close()
