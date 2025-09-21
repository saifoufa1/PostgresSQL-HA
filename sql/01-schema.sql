-- Schema definition for healthcare_db
\c healthcare_db;

-- Ensure UUID generation is available for default keys
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS medical_facilities (
  facility_id UUID PRIMARY KEY,
  facility_name TEXT NOT NULL,
  facility_type TEXT NOT NULL,
  address_line1 TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  zip_code TEXT NOT NULL,
  phone_number TEXT
);

CREATE TABLE IF NOT EXISTS healthcare_providers (
  provider_id UUID PRIMARY KEY,
  license_number TEXT NOT NULL UNIQUE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  specialty TEXT,
  department TEXT,
  phone_number TEXT,
  email TEXT,
  office_location TEXT,
  facility_id UUID REFERENCES medical_facilities(facility_id)
);

CREATE TABLE IF NOT EXISTS patients (
  patient_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  medical_record_number TEXT NOT NULL UNIQUE,
  first_name TEXT NOT NULL,
  last_name TEXT NOT NULL,
  date_of_birth DATE,
  gender TEXT,
  blood_type TEXT,
  phone_number TEXT,
  email TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  address_line1 TEXT,
  city TEXT,
  state TEXT,
  zip_code TEXT,
  insurance_provider TEXT,
  insurance_policy_number TEXT
);

CREATE TABLE IF NOT EXISTS appointments (
  appointment_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  provider_id UUID NOT NULL REFERENCES healthcare_providers(provider_id),
  facility_id UUID NOT NULL REFERENCES medical_facilities(facility_id),
  appointment_date DATE NOT NULL,
  appointment_time TIME NOT NULL,
  duration_minutes INTEGER,
  appointment_type TEXT,
  status TEXT,
  chief_complaint TEXT
);

CREATE TABLE IF NOT EXISTS medical_records (
  record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  provider_id UUID NOT NULL REFERENCES healthcare_providers(provider_id),
  appointment_id UUID REFERENCES appointments(appointment_id),
  record_date DATE NOT NULL,
  record_time TIME,
  chief_complaint TEXT,
  history_of_present_illness TEXT,
  physical_examination TEXT,
  assessment_and_plan TEXT,
  diagnosis_codes TEXT[] DEFAULT '{}',
  procedure_codes TEXT[] DEFAULT '{}',
  vital_signs JSONB
);

CREATE TABLE IF NOT EXISTS prescriptions (
  prescription_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  provider_id UUID NOT NULL REFERENCES healthcare_providers(provider_id),
  medical_record_id UUID REFERENCES medical_records(record_id),
  medication_name TEXT NOT NULL,
  dosage TEXT,
  frequency TEXT,
  quantity INTEGER,
  refills_allowed INTEGER,
  refills_remaining INTEGER,
  prescribed_date DATE,
  status TEXT,
  pharmacy_name TEXT
);

CREATE TABLE IF NOT EXISTS lab_results (
  lab_result_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  patient_id UUID NOT NULL REFERENCES patients(patient_id),
  provider_id UUID NOT NULL REFERENCES healthcare_providers(provider_id),
  medical_record_id UUID REFERENCES medical_records(record_id),
  test_name TEXT NOT NULL,
  test_code TEXT,
  result_value TEXT,
  reference_range TEXT,
  unit_of_measure TEXT,
  abnormal_flag TEXT,
  test_date DATE,
  result_date DATE,
  lab_name TEXT
);

CREATE INDEX IF NOT EXISTS idx_patients_last_name ON patients(last_name);
CREATE INDEX IF NOT EXISTS idx_appointments_patient ON appointments(patient_id);
CREATE INDEX IF NOT EXISTS idx_appointments_provider ON appointments(provider_id);
CREATE INDEX IF NOT EXISTS idx_medical_records_patient ON medical_records(patient_id);
CREATE INDEX IF NOT EXISTS idx_prescriptions_patient ON prescriptions(patient_id);
CREATE INDEX IF NOT EXISTS idx_lab_results_patient ON lab_results(patient_id);

CREATE TABLE IF NOT EXISTS audit_log (
  audit_id BIGSERIAL PRIMARY KEY,
  event_time TIMESTAMPTZ DEFAULT now(),
  actor TEXT,
  action TEXT,
  context JSONB
);
