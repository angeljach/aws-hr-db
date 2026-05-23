package main

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"os"
	"time"

	"github.com/aws/aws-lambda-go/lambda"
	_ "github.com/lib/pq"
	"local.aws-hr-db/shared"
)

type Employee struct {
	EmployeeID int    `json:"employee_id"`
	FirstName  string `json:"first_name"`
	LastName   string `json:"last_name"`
	Email      string `json:"email"`
	Department string `json:"department"`
	HireDate   string `json:"hire_date"`
	Phone      string `json:"-"`
	Address    string `json:"-"`
	Salary     string `json:"-"`
}

type ExtractRequest struct{}

type ExtractResponse struct {
	Message    string `json:"message"`
	RowsAdded  int    `json:"rows_added"`
	Timestamp  string `json:"timestamp"`
	StatusCode int    `json:"status_code"`
}

var dummyEmployees = []map[string]string{
	{"employee_id": "1", "first_name": "Juan", "last_name": "García", "email": "juan.garcia@company.com", "department": "Engineering", "hire_date": "2020-01-15", "phone": "555-0101", "address": "123 Main St", "salary": "75000"},
	{"employee_id": "2", "first_name": "María", "last_name": "López", "email": "maria.lopez@company.com", "department": "Sales", "hire_date": "2019-06-20", "phone": "555-0102", "address": "456 Oak Ave", "salary": "65000"},
	{"employee_id": "3", "first_name": "Carlos", "last_name": "Rodríguez", "email": "carlos.rodriguez@company.com", "department": "Engineering", "hire_date": "2021-03-10", "phone": "555-0103", "address": "789 Pine Rd", "salary": "80000"},
	{"employee_id": "4", "first_name": "Ana", "last_name": "Martínez", "email": "ana.martinez@company.com", "department": "HR", "hire_date": "2018-09-05", "phone": "555-0104", "address": "101 Elm St", "salary": "62000"},
	{"employee_id": "5", "first_name": "Luis", "last_name": "Fernández", "email": "luis.fernandez@company.com", "department": "Finance", "hire_date": "2017-11-12", "phone": "555-0105", "address": "202 Maple Dr", "salary": "70000"},
	{"employee_id": "6", "first_name": "Sofia", "last_name": "González", "email": "sofia.gonzalez@company.com", "department": "Marketing", "hire_date": "2020-07-22", "phone": "555-0106", "address": "303 Birch Ln", "salary": "68000"},
	{"employee_id": "7", "first_name": "Roberto", "last_name": "Sánchez", "email": "roberto.sanchez@company.com", "department": "Engineering", "hire_date": "2019-02-14", "phone": "555-0107", "address": "404 Cedar Ct", "salary": "82000"},
	{"employee_id": "8", "first_name": "Isabela", "last_name": "Pérez", "email": "isabela.perez@company.com", "department": "Product", "hire_date": "2021-08-30", "phone": "555-0108", "address": "505 Spruce Way", "salary": "76000"},
	{"employee_id": "9", "first_name": "Miguel", "last_name": "Torres", "email": "miguel.torres@company.com", "department": "Engineering", "hire_date": "2020-05-18", "phone": "555-0109", "address": "606 Walnut Blvd", "salary": "79000"},
	{"employee_id": "10", "first_name": "Elena", "last_name": "Ruiz", "email": "elena.ruiz@company.com", "department": "Finance", "hire_date": "2018-12-01", "phone": "555-0110", "address": "707 Ash Park", "salary": "71000"},
	{"employee_id": "11", "first_name": "Diego", "last_name": "Jiménez", "email": "diego.jimenez@company.com", "department": "Sales", "hire_date": "2019-10-25", "phone": "555-0111", "address": "808 Holly Pl", "salary": "67000"},
	{"employee_id": "12", "first_name": "Valentina", "last_name": "Castro", "email": "valentina.castro@company.com", "department": "HR", "hire_date": "2020-02-10", "phone": "555-0112", "address": "909 Ivy Ln", "salary": "63000"},
	{"employee_id": "13", "first_name": "Fernando", "last_name": "Vega", "email": "fernando.vega@company.com", "department": "Engineering", "hire_date": "2021-01-20", "phone": "555-0113", "address": "1010 Jade Rd", "salary": "81000"},
	{"employee_id": "14", "first_name": "Gabriela", "last_name": "Moreno", "email": "gabriela.moreno@company.com", "department": "Marketing", "hire_date": "2019-04-15", "phone": "555-0114", "address": "1111 Kale St", "salary": "69000"},
	{"employee_id": "15", "first_name": "Pablo", "last_name": "Ortiz", "email": "pablo.ortiz@company.com", "department": "Engineering", "hire_date": "2020-09-30", "phone": "555-0115", "address": "1212 Lemon Ave", "salary": "78000"},
	{"employee_id": "16", "first_name": "Natalia", "last_name": "Herrera", "email": "natalia.herrera@company.com", "department": "Product", "hire_date": "2018-08-22", "phone": "555-0116", "address": "1313 Mint Dr", "salary": "75000"},
	{"employee_id": "17", "first_name": "Andrés", "last_name": "Silva", "email": "andres.silva@company.com", "department": "Finance", "hire_date": "2019-03-11", "phone": "555-0117", "address": "1414 Nutmeg Ct", "salary": "72000"},
	{"employee_id": "18", "first_name": "Catalina", "last_name": "Molina", "email": "catalina.molina@company.com", "department": "Sales", "hire_date": "2020-11-05", "phone": "555-0118", "address": "1515 Oak Grove", "salary": "66000"},
	{"employee_id": "19", "first_name": "Javier", "last_name": "Ramos", "email": "javier.ramos@company.com", "department": "Engineering", "hire_date": "2021-06-14", "phone": "555-0119", "address": "1616 Pine Valley", "salary": "83000"},
	{"employee_id": "20", "first_name": "Martina", "last_name": "Campos", "email": "martina.campos@company.com", "department": "HR", "hire_date": "2017-07-03", "phone": "555-0120", "address": "1717 Quartz Hill", "salary": "64000"},
}

func handler(ctx context.Context, request ExtractRequest) (ExtractResponse, error) {
	log.Println("Starting extract and encrypt handler")

	encryptionKey := os.Getenv("ENCRYPTION_KEY")
	if encryptionKey == "" {
		return ExtractResponse{StatusCode: 500, Message: "ENCRYPTION_KEY not set"}, fmt.Errorf("ENCRYPTION_KEY not set")
	}

	db, err := connectDB()
	if err != nil {
		log.Printf("Database connection failed: %v", err)
		return ExtractResponse{StatusCode: 500, Message: "Database connection failed"}, err
	}
	defer db.Close()

	rowsAdded, err := insertEmployees(db, encryptionKey)
	if err != nil {
		log.Printf("Error inserting employees: %v", err)
		return ExtractResponse{StatusCode: 500, Message: "Error inserting employees"}, err
	}

	return ExtractResponse{
		Message:    "Extraction and encryption completed successfully",
		RowsAdded:  rowsAdded,
		Timestamp:  time.Now().UTC().Format(time.RFC3339),
		StatusCode: 200,
	}, nil
}

func connectDB() (*sql.DB, error) {
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbName := os.Getenv("DB_NAME")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=disable",
		dbUser, dbPassword, dbHost, dbPort, dbName)

	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}

	if err := db.Ping(); err != nil {
		return nil, err
	}

	return db, nil
}

func insertEmployees(db *sql.DB, encryptionKey string) (int, error) {
	// Create table if not exists
	createTableSQL := `
	CREATE TABLE IF NOT EXISTS employees (
		employee_id SERIAL PRIMARY KEY,
		first_name VARCHAR(100),
		last_name VARCHAR(100),
		email VARCHAR(100),
		department VARCHAR(100),
		hire_date DATE,
		phone_encrypted VARCHAR(500),
		address_encrypted VARCHAR(500),
		salary_encrypted VARCHAR(500),
		created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
	);
	`

	if _, err := db.Exec(createTableSQL); err != nil {
		return 0, err
	}

	rowsAdded := 0

	for _, emp := range dummyEmployees {
		// Encrypt sensitive fields
		encryptedPhone, err := shared.EncryptAES256GCM(emp["phone"], encryptionKey)
		if err != nil {
			log.Printf("Error encrypting phone: %v", err)
			continue
		}

		encryptedAddress, err := shared.EncryptAES256GCM(emp["address"], encryptionKey)
		if err != nil {
			log.Printf("Error encrypting address: %v", err)
			continue
		}

		encryptedSalary, err := shared.EncryptAES256GCM(emp["salary"], encryptionKey)
		if err != nil {
			log.Printf("Error encrypting salary: %v", err)
			continue
		}

		// Insert employee
		insertSQL := `
		INSERT INTO employees (employee_id, first_name, last_name, email, department, hire_date, phone_encrypted, address_encrypted, salary_encrypted)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (employee_id) DO NOTHING
		`

		result, err := db.Exec(insertSQL, emp["employee_id"], emp["first_name"], emp["last_name"],
			emp["email"], emp["department"], emp["hire_date"], encryptedPhone, encryptedAddress, encryptedSalary)
		if err != nil {
			log.Printf("Error inserting employee %s: %v", emp["employee_id"], err)
			continue
		}

		rowsAff, _ := result.RowsAffected()
		rowsAdded += int(rowsAff)
	}

	return rowsAdded, nil
}

func main() {
	lambda.Start(handler)
}
