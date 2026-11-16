use Healthstack;

drop trigger if exists trg_doctor_disjoint_before_insert;
drop trigger if exists trg_doctor_disjoint_before_update;
drop trigger if exists trg_nurse_disjoint_before_insert;
drop trigger if exists trg_nurse_disjoint_before_update;
drop trigger if exists trg_ward_boy_disjoint_before_insert;
drop trigger if exists trg_ward_boy_disjoint_before_update;
drop trigger if exists trg_receptionist_disjoint_before_insert;
drop trigger if exists trg_receptionist_disjoint_before_update;
drop trigger if exists trg_pharmacist_disjoint_before_insert;
drop trigger if exists trg_pharmacist_disjoint_before_update;
drop trigger if exists trg_doctor_role;
drop trigger if exists trg_doctor_role_bi;
drop trigger if exists trg_doctor_role_bu;
drop trigger if exists trg_nurse_role;
drop trigger if exists trg_nurse_role_bi;
drop trigger if exists trg_nurse_role_bu;
drop trigger if exists trg_ward_boy_role;
drop trigger if exists trg_ward_boy_role_bi;
drop trigger if exists trg_ward_boy_role_bu;
drop trigger if exists trg_receptionist_role;
drop trigger if exists trg_receptionist_role_bi;
drop trigger if exists trg_receptionist_role_bu;
drop trigger if exists trg_pharmacist_role;
drop trigger if exists trg_pharmacist_role_bi;
drop trigger if exists trg_pharmacist_role_bu;
drop trigger if exists trg_employee_role_lock;
drop procedure if exists check_employee_role;
drop procedure if exists onboard_employee;

delimiter //

create procedure check_employee_role(
    in p_emp_id int,
    in p_role varchar(20)
)
begin
    if not exists (
        select 1
        from Employee
        where Employee_id = p_emp_id
          and Role = p_role
    ) then
        signal sqlstate '45000'
            set message_text = 'employee does not exist or has a different role';
    end if;
end//

create trigger trg_doctor_role_bi
before insert on Doctor
for each row call check_employee_role(new.Employee_id, 'Doctor')//

create trigger trg_doctor_role_bu
before update on Doctor
for each row call check_employee_role(new.Employee_id, 'Doctor')//

create trigger trg_nurse_role_bi
before insert on Nurse
for each row call check_employee_role(new.Employee_id, 'Nurse')//

create trigger trg_nurse_role_bu
before update on Nurse
for each row call check_employee_role(new.Employee_id, 'Nurse')//

create trigger trg_ward_boy_role_bi
before insert on Ward_boy
for each row call check_employee_role(new.Employee_id, 'Ward_boy')//

create trigger trg_ward_boy_role_bu
before update on Ward_boy
for each row call check_employee_role(new.Employee_id, 'Ward_boy')//

create trigger trg_receptionist_role_bi
before insert on Receptionist
for each row call check_employee_role(new.Employee_id, 'Receptionist')//

create trigger trg_receptionist_role_bu
before update on Receptionist
for each row call check_employee_role(new.Employee_id, 'Receptionist')//



create trigger trg_pharmacist_role_bi
before insert on Pharmacist
for each row call check_employee_role(new.Employee_id, 'Pharmacist')//

create trigger trg_pharmacist_role_bu
before update on Pharmacist
for each row call check_employee_role(new.Employee_id, 'Pharmacist')//

create trigger trg_employee_role_lock
before update on Employee
for each row
begin
    if new.Role <> old.Role and (
           exists (select 1 from Doctor where Employee_id = old.Employee_id)
        or exists (select 1 from Nurse where Employee_id = old.Employee_id)
        or exists (select 1 from Ward_boy where Employee_id = old.Employee_id)
        or exists (select 1 from Receptionist where Employee_id = old.Employee_id)
        or exists (select 1 from Pharmacist where Employee_id = old.Employee_id)
    ) then
        signal sqlstate '45000'
            set message_text = 'remove the employee from their subclass table before changing role';
    end if;
end//

-- Employee onboarding transaction: adds the Employee row and its subclass row together,
-- or neither. The triggers above check each row; this keeps the pair consistent, so no
-- employee is left without a subclass row. Pass NULL for the arguments a role does not use:
--   Doctor:       p_license_no and p_dept_id required; p_fee defaults to 200
--   Ward_boy:     p_ward_id required
--   Receptionist: p_desk_no required
--   Nurse, Pharmacist: no extra arguments
-- Example:
--   call onboard_employee(106, 'Asha', 'Menon', 'Female', '1990-02-14', curdate(),
--        'asha@demo.com', 118000, 'Doctor', 'DEMO-CARD-106', 2, 200, null, null);
-- Run it on its own, not inside another transaction: START TRANSACTION below would
-- commit any open one first. It does not create a login; staff logins are AuthAccount rows.
create procedure onboard_employee(
    in p_employee_id int,
    in p_first_name  varchar(50),
    in p_last_name   varchar(50),
    in p_gender      varchar(10),
    in p_dob         date,
    in p_date_join   date,
    in p_mail        varchar(100),
    in p_salary      decimal(10, 2),
    in p_role        varchar(20),
    in p_license_no  varchar(50),
    in p_dept_id     int,
    in p_fee         decimal(10, 2),
    in p_ward_id     int,
    in p_desk_no     varchar(20)
)
begin
    -- Any error (a constraint, a trigger's SIGNAL, a duplicate key) undoes both rows
    -- and is passed back to the caller unchanged.
    declare exit handler for sqlexception
    begin
        rollback;
        resignal;
    end;

    start transaction;

    insert into Employee (Employee_id, First_name, Last_name, Gender, DOB, Date_join, Mail, Salary, Role)
    values (p_employee_id, p_first_name, p_last_name, p_gender, p_dob, p_date_join, p_mail, p_salary, p_role);

    case p_role
        when 'Doctor' then
            insert into Doctor (Employee_id, License_no, Dept_id, Consultation_fee)
            values (p_employee_id, p_license_no, p_dept_id, coalesce(p_fee, 200));
        when 'Nurse' then
            insert into Nurse (Employee_id) values (p_employee_id);
        when 'Ward_boy' then
            insert into Ward_boy (Employee_id, Ward_id) values (p_employee_id, p_ward_id);
        when 'Receptionist' then
            insert into Receptionist (Employee_id, Desk_no) values (p_employee_id, p_desk_no);
        when 'Pharmacist' then
            insert into Pharmacist (Employee_id) values (p_employee_id);
        else
            signal sqlstate '45000'
                set message_text = 'this role has no subclass table yet';
    end case;

    commit;
end//

delimiter ;


