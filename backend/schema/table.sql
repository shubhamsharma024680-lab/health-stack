-- This resets the application's tables and data (tables only).
-- Triggers live in backend/triggers/: run backend/triggers/install.sql after this file,
-- then backend/seed/seed.sql.

create database if not exists Healthstack;
use Healthstack;
SET time_zone = '+05:30';

-- Reset login sessions/accounts too, so sourcing both files again works.
drop table if exists AuthSession;
drop table if exists AuthAccount;

drop table if exists Bill;
drop table if exists Pres_Details;
drop table if exists Medicine;
drop table if exists Prescription;
drop table if exists Appointment;
drop table if exists Patient;
drop table if exists Pharmacist;
drop table if exists Receptionist;
drop table if exists Ward_boy;
drop table if exists Ward;
drop table if exists Nurse;
drop table if exists Doctor;
drop table if exists Employee;
drop table if exists Department;

create table Department (
    Dept_id int,
    Dept_name varchar(100) unique not null,
    Description text,
    primary key (Dept_id)
);

create table Employee (
    Employee_id int,
    First_name varchar(50) not null,
    Last_name varchar(50) not null,
    Gender varchar(10) not null,
    DOB date not null,
    Date_join date not null,
    Mail varchar(100) unique not null,
    Salary decimal(10, 2) not null,
    Role varchar(20) not null,
    Is_active boolean not null default true,
    primary key (Employee_id),
    check (Gender in ('Male', 'Female', 'Other')),
    check (Salary >= 0),
    check (Role in ('Doctor', 'Nurse', 'Ward_boy', 'Receptionist', 'Technician', 'Pharmacist')),
    check (Date_join > DOB)
);

create table Doctor (
    Employee_id int,
    License_no varchar(50) unique not null,
    Current_appointment_id int null,
    Dept_id int not null,
    Consultation_fee decimal(10, 2) not null default 200,
    primary key (Employee_id),
    foreign key (Employee_id) references Employee(Employee_id) on delete cascade,
    foreign key (Dept_id) references Department(Dept_id) on delete restrict,
    check (Consultation_fee >= 0)
);

create table Nurse (
    Employee_id int,
    primary key (Employee_id),
    foreign key (Employee_id) references Employee(Employee_id) on delete cascade
);

create table Ward (
    Ward_id int,
    Ward_name varchar(50) unique not null,
    Capacity int not null,
    primary key (Ward_id),
    check (Capacity > 0)
);

create table Ward_boy (
    Employee_id int,
    Ward_id int not null,
    primary key (Employee_id),
    foreign key (Employee_id) references Employee(Employee_id) on delete cascade,
    foreign key (Ward_id) references Ward(Ward_id) on delete restrict
);

create table Receptionist (
    Employee_id int,
    Desk_no varchar(20) not null,
    primary key (Employee_id),
    foreign key (Employee_id) references Employee(Employee_id) on delete cascade
);

create table Pharmacist (
    Employee_id int,
    primary key (Employee_id),
    foreign key (Employee_id) references Employee(Employee_id) on delete cascade
);

create table Patient (
    Patient_id int auto_increment,
    First_name varchar(50) not null,
    Last_name varchar(50) not null,
    Gender varchar(10) not null,
    DOB date not null,
    Mail varchar(100),
    Contact varchar(20) not null,
    Street varchar(100),
    City varchar(50),
    State varchar(50),
    History text,
    primary key (Patient_id),
    check (Gender in ('Male', 'Female', 'Other'))
);

create table Appointment (
    Appointment_id int auto_increment,
    Patient_id int not null,
    Doctor_id int not null,
    App_date date not null,
    App_time time not null,
    App_status varchar(20) not null default 'Scheduled',
    Active_slot tinyint as (if(App_status = 'Cancelled', null, 1)) stored,
    unique (Doctor_id, App_date, App_time, Active_slot),
    unique (Patient_id, App_date, App_time, Active_slot),
    primary key (Appointment_id),
    foreign key (Patient_id) references Patient(Patient_id) on delete restrict,
    foreign key (Doctor_id) references Doctor(Employee_id) on delete restrict,
    check (App_status in ('Scheduled', 'Completed', 'Cancelled'))
);

create table Prescription (
    Pres_id int auto_increment,
    Appointment_id int unique not null,
    Pres_date date not null,
    Notes text,
    Valid_until date not null,
    primary key (Pres_id),
    foreign key (Appointment_id) references Appointment(Appointment_id) on delete restrict
);

create table Medicine (
    Med_id int,
    Med_name varchar(100) not null,
    Price decimal(10, 2) not null,
    primary key (Med_id),
    check (Price >= 0)
);

create table Pres_Details (
    Pres_id int not null,
    Med_id int not null,
    Dosage varchar(50) not null,
    Quantity int not null,
    Frequency varchar(50) not null,
    Unit_price decimal(10, 2) not null default 0,
    primary key (Pres_id, Med_id),
    foreign key (Pres_id) references Prescription(Pres_id) on delete cascade,
    foreign key (Med_id) references Medicine(Med_id) on delete restrict,
    check (Quantity > 0),
    check (Unit_price >= 0)
);

create table Bill (
    Bill_id int auto_increment,
    Appointment_id int unique not null,
    Consultation_fee decimal(10, 2) not null default 200,
    Bill_amount decimal(10, 2) not null default 200,
    Bill_date date not null,
    Paid_date date null,
    Payment_status varchar(10) not null default 'Pending',
    Payment_mode varchar(50) null,
    primary key (Bill_id),
    foreign key (Appointment_id) references Appointment(Appointment_id) on delete restrict,
    check (Consultation_fee >= 0),
    check (Bill_amount >= 0),
    check (Payment_status in ('Pending', 'Paid')),
    check (Payment_mode in ('Cash', 'Card', 'UPI', 'Insurance', 'NetBanking')),
    check (Payment_status = 'Pending' or Payment_mode is not null)
);

CREATE TABLE IF NOT EXISTS AuthAccount (
    Account_id INT AUTO_INCREMENT PRIMARY KEY,
    Email VARCHAR(100) NOT NULL UNIQUE,
    Password_hash VARCHAR(255) NOT NULL,
    Role ENUM('patient','doctor','pharmacist') NOT NULL,
    User_id INT NOT NULL,
    UNIQUE (Role, User_id)
);
-- User_id is Patient.Patient_id for patients, Employee.Employee_id for staff.
CREATE TABLE IF NOT EXISTS AuthSession (
    Token_hash CHAR(64) PRIMARY KEY,
    Account_id INT NOT NULL,
    Expires_at DATETIME NOT NULL,
    FOREIGN KEY (Account_id) REFERENCES AuthAccount(Account_id) ON DELETE CASCADE
);
