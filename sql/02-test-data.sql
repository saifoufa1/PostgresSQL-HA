-- Sample Test Data for Healthcare Database
-- This script provides minimal test data to populate the healthcare database schema
-- Run this after creating the schema with sample-schema.sql

-- Connect to the healthcare database
\c healthcare_db;

-- Insert sample medical facilities
INSERT INTO medical_facilities (facility_id, facility_name, facility_type, address_line1, city, state, zip_code, phone_number) VALUES
('550e8400-e29b-41d4-a716-446655440001', 'General Hospital', 'hospital', '123 Main Street', 'Springfield', 'IL', '62701', '217-555-0100'),
('550e8400-e29b-41d4-a716-446655440002', 'Family Health Clinic', 'clinic', '456 Oak Avenue', 'Springfield', 'IL', '62702', '217-555-0200'),
('550e8400-e29b-41d4-a716-446655440003', 'Urgent Care Center', 'urgent_care', '789 Pine Street', 'Springfield', 'IL', '62703', '217-555-0300');

-- Insert sample healthcare providers
INSERT INTO healthcare_providers (provider_id, license_number, first_name, last_name, specialty, department, phone_number, email, office_location) VALUES
('660e8400-e29b-41d4-a716-446655440001', 'MD123456', 'Sarah', 'Johnson', 'Internal Medicine', 'Internal Medicine', '217-555-1001', 'sarah.johnson@hospital.com', 'Building A, Suite 101'),
('660e8400-e29b-41d4-a716-446655440002', 'MD123457', 'Michael', 'Chen', 'Cardiology', 'Cardiology', '217-555-1002', 'michael.chen@hospital.com', 'Building B, Suite 201'),
('660e8400-e29b-41d4-a716-446655440003', 'MD123458', 'Emily', 'Rodriguez', 'Pediatrics', 'Pediatrics', '217-555-1003', 'emily.rodriguez@clinic.com', 'Building C, Suite 301'),
('660e8400-e29b-41d4-a716-446655440004', 'MD123459', 'David', 'Thompson', 'Emergency Medicine', 'Emergency Department', '217-555-1004', 'david.thompson@hospital.com', 'Emergency Department'),
('660e8400-e29b-41d4-a716-446655440005', 'MD123460', 'Lisa', 'Anderson', 'Family Medicine', 'Family Medicine', '217-555-1005', 'lisa.anderson@clinic.com', 'Building D, Suite 401');

-- Insert sample patients
INSERT INTO patients (patient_id, medical_record_number, first_name, last_name, date_of_birth, gender, blood_type, phone_number, email, emergency_contact_name, emergency_contact_phone, address_line1, city, state, zip_code, insurance_provider, insurance_policy_number) VALUES
('770e8400-e29b-41d4-a716-446655440001', 'MRN001001', 'John', 'Smith', '1985-03-15', 'male', 'O+', '217-555-2001', 'john.smith@email.com', 'Jane Smith', '217-555-2002', '100 Elm Street', 'Springfield', 'IL', '62701', 'Blue Cross Blue Shield', 'BCBS123456'),
('770e8400-e29b-41d4-a716-446655440002', 'MRN001002', 'Maria', 'Garcia', '1990-07-22', 'female', 'A+', '217-555-2003', 'maria.garcia@email.com', 'Carlos Garcia', '217-555-2004', '200 Maple Avenue', 'Springfield', 'IL', '62702', 'Aetna', 'AETNA789012'),
('770e8400-e29b-41d4-a716-446655440003', 'MRN001003', 'Robert', 'Williams', '1975-11-08', 'male', 'B+', '217-555-2005', 'robert.williams@email.com', 'Susan Williams', '217-555-2006', '300 Cedar Lane', 'Springfield', 'IL', '62703', 'Cigna', 'CIGNA345678'),
('770e8400-e29b-41d4-a716-446655440004', 'MRN001004', 'Jennifer', 'Brown', '1988-01-30', 'female', 'AB-', '217-555-2007', 'jennifer.brown@email.com', 'Michael Brown', '217-555-2008', '400 Birch Road', 'Springfield', 'IL', '62704', 'United Healthcare', 'UHC901234'),
('770e8400-e29b-41d4-a716-446655440005', 'MRN001005', 'Christopher', 'Davis', '1992-09-12', 'male', 'O-', '217-555-2009', 'christopher.davis@email.com', 'Ashley Davis', '217-555-2010', '500 Willow Street', 'Springfield', 'IL', '62705', 'Humana', 'HUM567890'),
('770e8400-e29b-41d4-a716-446655440006', 'MRN001006', 'Amanda', 'Miller', '1983-05-18', 'female', 'A-', '217-555-2011', 'amanda.miller@email.com', 'James Miller', '217-555-2012', '600 Spruce Avenue', 'Springfield', 'IL', '62706', 'Blue Cross Blue Shield', 'BCBS654321'),
('770e8400-e29b-41d4-a716-446655440007', 'MRN001007', 'Daniel', 'Wilson', '1978-12-03', 'male', 'B-', '217-555-2013', 'daniel.wilson@email.com', 'Lisa Wilson', '217-555-2014', '700 Poplar Drive', 'Springfield', 'IL', '62707', 'Kaiser Permanente', 'KP123789'),
('770e8400-e29b-41d4-a716-446655440008', 'MRN001008', 'Sarah', 'Taylor', '1995-04-25', 'female', 'O+', '217-555-2015', 'sarah.taylor@email.com', 'Mark Taylor', '217-555-2016', '800 Chestnut Circle', 'Springfield', 'IL', '62708', 'Aetna', 'AETNA456123'),
('770e8400-e29b-41d4-a716-446655440009', 'MRN001009', 'Kevin', 'Anderson', '1987-08-14', 'male', 'AB+', '217-555-2017', 'kevin.anderson@email.com', 'Michelle Anderson', '217-555-2018', '900 Hickory Lane', 'Springfield', 'IL', '62709', 'Cigna', 'CIGNA789456'),
('770e8400-e29b-41d4-a716-446655440010', 'MRN001010', 'Michelle', 'Thomas', '1991-06-07', 'female', 'A+', '217-555-2019', 'michelle.thomas@email.com', 'Ryan Thomas', '217-555-2020', '1000 Walnut Street', 'Springfield', 'IL', '62710', 'United Healthcare', 'UHC147258');

-- Insert sample appointments (mix of past, current, and future)
INSERT INTO appointments (appointment_id, patient_id, provider_id, facility_id, appointment_date, appointment_time, duration_minutes, appointment_type, status, chief_complaint) VALUES
('880e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', '2024-01-15', '09:00:00', 30, 'consultation', 'completed', 'Annual physical examination'),
('880e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', '2024-01-16', '10:30:00', 45, 'consultation', 'completed', 'Chest pain evaluation'),
('880e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440003', '660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440002', '2024-01-17', '14:00:00', 30, 'follow_up', 'completed', 'Diabetes management follow-up'),
('880e8400-e29b-41d4-a716-446655440004', '770e8400-e29b-41d4-a716-446655440004', '660e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440002', '2024-01-18', '11:15:00', 30, 'consultation', 'completed', 'Child wellness check'),
('880e8400-e29b-41d4-a716-446655440005', '770e8400-e29b-41d4-a716-446655440005', '660e8400-e29b-41d4-a716-446655440004', '550e8400-e29b-41d4-a716-446655440003', '2024-01-19', '16:45:00', 60, 'procedure', 'completed', 'Minor laceration repair'),
('880e8400-e29b-41d4-a716-446655440006', '770e8400-e29b-41d4-a716-446655440006', '660e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440002', '2024-02-01', '08:30:00', 30, 'consultation', 'scheduled', 'Hypertension management'),
('880e8400-e29b-41d4-a716-446655440007', '770e8400-e29b-41d4-a716-446655440007', '660e8400-e29b-41d4-a716-446655440002', '550e8400-e29b-41d4-a716-446655440001', '2024-02-02', '13:00:00', 45, 'consultation', 'confirmed', 'Cardiac stress test'),
('880e8400-e29b-41d4-a716-446655440008', '770e8400-e29b-41d4-a716-446655440008', '660e8400-e29b-41d4-a716-446655440003', '550e8400-e29b-41d4-a716-446655440002', '2024-02-03', '15:30:00', 30, 'consultation', 'scheduled', 'Vaccination appointment'),
('880e8400-e29b-41d4-a716-446655440009', '770e8400-e29b-41d4-a716-446655440009', '660e8400-e29b-41d4-a716-446655440001', '550e8400-e29b-41d4-a716-446655440001', '2024-02-04', '10:00:00', 30, 'follow_up', 'scheduled', 'Lab results review'),
('880e8400-e29b-41d4-a716-446655440010', '770e8400-e29b-41d4-a716-446655440010', '660e8400-e29b-41d4-a716-446655440005', '550e8400-e29b-41d4-a716-446655440002', '2024-02-05', '12:15:00', 30, 'consultation', 'scheduled', 'Prenatal checkup');

-- Insert sample medical records
INSERT INTO medical_records (record_id, patient_id, provider_id, appointment_id, record_date, record_time, chief_complaint, history_of_present_illness, physical_examination, assessment_and_plan, diagnosis_codes, procedure_codes, vital_signs) VALUES
('990e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '880e8400-e29b-41d4-a716-446655440001', '2024-01-15', '09:00:00', 'Annual physical examination', 'Patient presents for routine annual physical. No acute concerns. Reports feeling well overall.', 'Vital signs stable. Physical examination unremarkable. No acute distress.', 'Continue current health maintenance. Recommend routine screening labs.', ARRAY['Z00.00'], ARRAY['99213'], '{"temperature": 98.6, "blood_pressure": "120/80", "heart_rate": 72, "respiratory_rate": 16, "oxygen_saturation": 99}'),
('990e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002', '880e8400-e29b-41d4-a716-446655440002', '2024-01-16', '10:30:00', 'Chest pain evaluation', 'Patient reports intermittent chest pain for 2 days. Pain described as sharp, non-radiating.', 'Cardiovascular examination normal. No murmurs. Lungs clear bilaterally.', 'Likely musculoskeletal chest pain. EKG normal. Discharge with follow-up instructions.', ARRAY['R06.02'], ARRAY['99214', '93000'], '{"temperature": 98.4, "blood_pressure": "118/76", "heart_rate": 68, "respiratory_rate": 14, "oxygen_saturation": 100}'),
('990e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440003', '660e8400-e29b-41d4-a716-446655440001', '880e8400-e29b-41d4-a716-446655440003', '2024-01-17', '14:00:00', 'Diabetes management follow-up', 'Patient with Type 2 diabetes mellitus for follow-up. Reports good adherence to medications.', 'Physical examination stable. No diabetic complications noted.', 'Diabetes well controlled. Continue current regimen. HbA1c to be checked.', ARRAY['E11.9'], ARRAY['99213'], '{"temperature": 98.8, "blood_pressure": "130/85", "heart_rate": 75, "respiratory_rate": 16, "weight": 180}');

-- Insert sample prescriptions
INSERT INTO prescriptions (prescription_id, patient_id, provider_id, medical_record_id, medication_name, dosage, frequency, quantity, refills_allowed, refills_remaining, prescribed_date, status, pharmacy_name) VALUES
('aa0e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440003', '660e8400-e29b-41d4-a716-446655440001', '990e8400-e29b-41d4-a716-446655440003', 'Metformin', '500mg', 'Twice daily', 60, 3, 3, '2024-01-17', 'prescribed', 'Springfield Pharmacy'),
('aa0e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002', '990e8400-e29b-41d4-a716-446655440002', 'Ibuprofen', '400mg', 'As needed for pain', 30, 0, 0, '2024-01-16', 'filled', 'Main Street Pharmacy'),
('aa0e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '990e8400-e29b-41d4-a716-446655440001', 'Multivitamin', 'One tablet', 'Daily', 90, 2, 2, '2024-01-15', 'prescribed', 'Health Plus Pharmacy');

-- Insert sample lab results
INSERT INTO lab_results (lab_result_id, patient_id, provider_id, medical_record_id, test_name, test_code, result_value, reference_range, unit_of_measure, abnormal_flag, test_date, result_date, lab_name) VALUES
('bb0e8400-e29b-41d4-a716-446655440001', '770e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '990e8400-e29b-41d4-a716-446655440001', 'Complete Blood Count', 'CBC', '12.5', '12.0-15.5', 'g/dL', 'normal', '2024-01-15', '2024-01-15', 'Springfield Lab Services'),
('bb0e8400-e29b-41d4-a716-446655440002', '770e8400-e29b-41d4-a716-446655440001', '660e8400-e29b-41d4-a716-446655440001', '990e8400-e29b-41d4-a716-446655440001', 'Total Cholesterol', 'CHOL', '195', '<200', 'mg/dL', 'normal', '2024-01-15', '2024-01-15', 'Springfield Lab Services'),
('bb0e8400-e29b-41d4-a716-446655440003', '770e8400-e29b-41d4-a716-446655440003', '660e8400-e29b-41d4-a716-446655440001', '990e8400-e29b-41d4-a716-446655440003', 'Hemoglobin A1c', 'HBA1C', '7.2', '<7.0', '%', 'high', '2024-01-17', '2024-01-17', 'Springfield Lab Services'),
('bb0e8400-e29b-41d4-a716-446655440004', '770e8400-e29b-41d4-a716-446655440002', '660e8400-e29b-41d4-a716-446655440002', '990e8400-e29b-41d4-a716-446655440002', 'Troponin I', 'TROP', '0.02', '<0.04', 'ng/mL', 'normal', '2024-01-16', '2024-01-16', 'Emergency Lab Services');

-- Insert some additional patients for volume testing
INSERT INTO patients (medical_record_number, first_name, last_name, date_of_birth, gender, blood_type, phone_number, email, address_line1, city, state, zip_code, insurance_provider, insurance_policy_number) VALUES
('MRN001011', 'James', 'Moore', '1980-02-14', 'male', 'O+', '217-555-3001', 'james.moore@email.com', '1100 Oak Street', 'Springfield', 'IL', '62711', 'Blue Cross Blue Shield', 'BCBS111222'),
('MRN001012', 'Patricia', 'Jackson', '1985-09-21', 'female', 'A-', '217-555-3002', 'patricia.jackson@email.com', '1200 Pine Avenue', 'Springfield', 'IL', '62712', 'Aetna', 'AETNA333444'),
('MRN001013', 'William', 'White', '1972-11-30', 'male', 'B+', '217-555-3003', 'william.white@email.com', '1300 Cedar Drive', 'Springfield', 'IL', '62713', 'Cigna', 'CIGNA555666'),
('MRN001014', 'Linda', 'Harris', '1993-04-08', 'female', 'AB+', '217-555-3004', 'linda.harris@email.com', '1400 Maple Lane', 'Springfield', 'IL', '62714', 'United Healthcare', 'UHC777888'),
('MRN001015', 'Richard', 'Martin', '1988-07-19', 'male', 'O-', '217-555-3005', 'richard.martin@email.com', '1500 Elm Circle', 'Springfield', 'IL', '62715', 'Humana', 'HUM999000');

-- Create some test queries for candidates to use
-- These demonstrate the types of queries the system should handle efficiently

-- Query 1: Patient lookup by medical record number (common operation)
-- SELECT * FROM patients WHERE medical_record_number = 'MRN001001';

-- Query 2: Provider schedule for today
-- SELECT a.appointment_time, p.first_name, p.last_name, a.appointment_type, a.chief_complaint
-- FROM appointments a
-- JOIN patients p ON a.patient_id = p.patient_id
-- WHERE a.provider_id = '660e8400-e29b-41d4-a716-446655440001'
-- AND a.appointment_date = CURRENT_DATE
-- ORDER BY a.appointment_time;

-- Query 3: Recent lab results for a patient
-- SELECT lr.test_name, lr.result_value, lr.reference_range, lr.abnormal_flag, lr.test_date
-- FROM lab_results lr
-- WHERE lr.patient_id = '770e8400-e29b-41d4-a716-446655440001'
-- AND lr.test_date >= CURRENT_DATE - INTERVAL '90 days'
-- ORDER BY lr.test_date DESC;

-- Query 4: Active prescriptions for a patient
-- SELECT pr.medication_name, pr.dosage, pr.frequency, pr.prescribed_date, pr.refills_remaining
-- FROM prescriptions pr
-- WHERE pr.patient_id = '770e8400-e29b-41d4-a716-446655440003'
-- AND pr.status IN ('prescribed', 'partially_filled')
-- ORDER BY pr.prescribed_date DESC;

-- Query 5: Appointment statistics by provider
-- SELECT hp.first_name, hp.last_name, hp.specialty,
--        COUNT(CASE WHEN a.status = 'completed' THEN 1 END) as completed_appointments,
--        COUNT(CASE WHEN a.status = 'scheduled' THEN 1 END) as scheduled_appointments,
--        COUNT(CASE WHEN a.status = 'cancelled' THEN 1 END) as cancelled_appointments
-- FROM healthcare_providers hp
-- LEFT JOIN appointments a ON hp.provider_id = a.provider_id
-- WHERE a.appointment_date >= CURRENT_DATE - INTERVAL '30 days'
-- GROUP BY hp.provider_id, hp.first_name, hp.last_name, hp.specialty;

-- Add some comments for candidates
COMMENT ON TABLE patients IS 'This table will experience high read volume for patient lookups';
COMMENT ON TABLE appointments IS 'This table will have high insert/update volume during business hours';
COMMENT ON TABLE medical_records IS 'Critical table for clinical data - must be highly available';
COMMENT ON TABLE audit_log IS 'Audit trail - consider archiving strategy for large volumes';

-- Display summary of inserted data
SELECT 'Data Loading Summary' as summary;
SELECT 'Medical Facilities' as table_name, COUNT(*) as record_count FROM medical_facilities
UNION ALL
SELECT 'Healthcare Providers', COUNT(*) FROM healthcare_providers
UNION ALL
SELECT 'Patients', COUNT(*) FROM patients
UNION ALL
SELECT 'Appointments', COUNT(*) FROM appointments
UNION ALL
SELECT 'Medical Records', COUNT(*) FROM medical_records
UNION ALL
SELECT 'Prescriptions', COUNT(*) FROM prescriptions
UNION ALL
SELECT 'Lab Results', COUNT(*) FROM lab_results;

-- Show some sample data for verification
SELECT 'Sample Patient Data' as info;
SELECT medical_record_number, first_name, last_name, date_of_birth, gender 
FROM patients 
LIMIT 5;

SELECT 'Sample Appointment Data' as info;
SELECT a.appointment_date, a.appointment_time, p.first_name as patient_name, 
       hp.first_name as provider_name, a.status
FROM appointments a
JOIN patients p ON a.patient_id = p.patient_id
JOIN healthcare_providers hp ON a.provider_id = hp.provider_id
LIMIT 5;
