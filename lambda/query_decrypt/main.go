package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"strconv"
	"strings"

	"github.com/aws/aws-lambda-go/events"
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
	Phone      *string `json:"phone,omitempty"`
	Address    *string `json:"address,omitempty"`
	Salary     *string `json:"salary,omitempty"`
}

type QueryResponse struct {
	Employees  []Employee `json:"employees"`
	Page       int        `json:"page"`
	Limit      int        `json:"limit"`
	Total      int        `json:"total"`
	StatusCode int        `json:"status_code"`
}

type ErrorResponse struct {
	Error      string `json:"error"`
	StatusCode int    `json:"status_code"`
}

const (
	DefaultLimit = 10
	MaxLimit     = 100
)

var roleAccess = map[string][]string{
	"admin": {"employee_id", "first_name", "last_name", "email", "department", "hire_date", "phone", "address", "salary"},
	"limited": {"employee_id", "first_name", "last_name", "email", "department", "hire_date"},
	"premium": {"employee_id", "first_name", "last_name", "email", "department", "hire_date", "phone"},
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	// Never log request.Headers or request.MultiValueHeaders — they contain the
	// Authorization bearer token, which CloudWatch readers could replay.
	log.Printf("Received request: method=%s path=%s query=%v user=%s requestId=%s",
		request.HTTPMethod, request.Path, request.QueryStringParameters,
		extractUsername(request), request.RequestContext.RequestID)

	// Extract user role from Cognito claims
	userRole := extractUserRole(request)
	if userRole == "" {
		userRole = "limited" // default role
	}
	log.Printf("User role: %s", userRole)

	encryptionKey := os.Getenv("ENCRYPTION_KEY")
	if encryptionKey == "" {
		return createErrorResponse(500, "ENCRYPTION_KEY not set"), nil
	}

	db, err := connectDB()
	if err != nil {
		log.Printf("Database connection failed: %v", err)
		return createErrorResponse(500, "Database connection failed"), nil
	}
	defer db.Close()

	// Check if this is a single employee query or list
	id := request.PathParameters["id"]
	if id != "" {
		return handleGetEmployee(db, id, userRole, encryptionKey)
	}

	return handleListEmployees(db, request, userRole, encryptionKey)
}

func extractUserRole(request events.APIGatewayProxyRequest) string {
	// Try to extract from requestContext (Cognito groups).
	// API Gateway's Cognito authorizer flattens claim values to strings, so
	// cognito:groups arrives as "admin" (single group) or "admin,premium"
	// (multiple). When the claim is consumed elsewhere (custom authorizer,
	// raw JWT) it may still be []interface{} — handle both.
	if len(request.RequestContext.Authorizer) > 0 {
		if claims, ok := request.RequestContext.Authorizer["claims"].(map[string]interface{}); ok {
			switch v := claims["cognito:groups"].(type) {
			case string:
				if v != "" {
					// Trim "[ ... ]" if Cognito serialized as a JSON-ish string.
					trimmed := strings.Trim(v, "[]")
					if first, _, found := strings.Cut(trimmed, ","); found {
						return strings.TrimSpace(first)
					}
					return strings.TrimSpace(trimmed)
				}
			case []interface{}:
				if len(v) > 0 {
					if group, ok := v[0].(string); ok {
						return group
					}
				}
			}
		}
	}
	return ""
}

func extractUsername(request events.APIGatewayProxyRequest) string {
	if len(request.RequestContext.Authorizer) > 0 {
		if claims, ok := request.RequestContext.Authorizer["claims"].(map[string]interface{}); ok {
			if username, ok := claims["cognito:username"].(string); ok {
				return username
			}
		}
	}
	return "anonymous"
}

func handleListEmployees(db *sql.DB, request events.APIGatewayProxyRequest, userRole, encryptionKey string) (events.APIGatewayProxyResponse, error) {
	page := 1
	limit := DefaultLimit

	if pageStr := request.QueryStringParameters["page"]; pageStr != "" {
		if p, err := strconv.Atoi(pageStr); err == nil && p > 0 {
			page = p
		}
	}

	if limitStr := request.QueryStringParameters["limit"]; limitStr != "" {
		if l, err := strconv.Atoi(limitStr); err == nil && l > 0 && l <= MaxLimit {
			limit = l
		}
	}

	offset := (page - 1) * limit

	// Get total count
	var total int
	err := db.QueryRow("SELECT COUNT(*) FROM employees").Scan(&total)
	if err != nil {
		log.Printf("Error getting count: %v", err)
		return createErrorResponse(500, "Error querying database"), nil
	}

	// Get paginated employees
	rows, err := db.Query("SELECT employee_id, first_name, last_name, email, department, hire_date, phone_encrypted, address_encrypted, salary_encrypted FROM employees ORDER BY employee_id LIMIT $1 OFFSET $2", limit, offset)
	if err != nil {
		log.Printf("Error querying employees: %v", err)
		return createErrorResponse(500, "Error querying database"), nil
	}
	defer rows.Close()

	var employees []Employee
	allowedFields := roleAccess[userRole]

	for rows.Next() {
		var (
			id                     int
			firstName, lastName    string
			email, department      string
			hireDate               string
			phoneEncrypted         sql.NullString
			addressEncrypted       sql.NullString
			salaryEncrypted        sql.NullString
		)

		if err := rows.Scan(&id, &firstName, &lastName, &email, &department, &hireDate, &phoneEncrypted, &addressEncrypted, &salaryEncrypted); err != nil {
			log.Printf("Error scanning row: %v", err)
			continue
		}

		emp := Employee{
			EmployeeID: id,
			FirstName:  firstName,
			LastName:   lastName,
			Email:      email,
			Department: department,
			HireDate:   hireDate,
		}

		// Decrypt sensitive fields based on role
		if contains(allowedFields, "phone") && phoneEncrypted.Valid {
			if decrypted, err := shared.DecryptAES256GCM(phoneEncrypted.String, encryptionKey); err == nil {
				emp.Phone = &decrypted
			}
		}

		if contains(allowedFields, "address") && addressEncrypted.Valid {
			if decrypted, err := shared.DecryptAES256GCM(addressEncrypted.String, encryptionKey); err == nil {
				emp.Address = &decrypted
			}
		}

		if contains(allowedFields, "salary") && salaryEncrypted.Valid {
			if decrypted, err := shared.DecryptAES256GCM(salaryEncrypted.String, encryptionKey); err == nil {
				emp.Salary = &decrypted
			}
		}

		employees = append(employees, emp)
	}

	response := QueryResponse{
		Employees:  employees,
		Page:       page,
		Limit:      limit,
		Total:      total,
		StatusCode: 200,
	}

	body, _ := json.Marshal(response)
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func handleGetEmployee(db *sql.DB, idStr, userRole, encryptionKey string) (events.APIGatewayProxyResponse, error) {
	id, err := strconv.Atoi(idStr)
	if err != nil {
		return createErrorResponse(400, "Invalid employee ID"), nil
	}

	var (
		firstName, lastName    string
		email, department      string
		hireDate               string
		phoneEncrypted         sql.NullString
		addressEncrypted       sql.NullString
		salaryEncrypted        sql.NullString
	)

	err = db.QueryRow("SELECT employee_id, first_name, last_name, email, department, hire_date, phone_encrypted, address_encrypted, salary_encrypted FROM employees WHERE employee_id = $1", id).
		Scan(&id, &firstName, &lastName, &email, &department, &hireDate, &phoneEncrypted, &addressEncrypted, &salaryEncrypted)
	if err == sql.ErrNoRows {
		return createErrorResponse(404, "Employee not found"), nil
	}
	if err != nil {
		log.Printf("Error querying employee: %v", err)
		return createErrorResponse(500, "Error querying database"), nil
	}

	emp := Employee{
		EmployeeID: id,
		FirstName:  firstName,
		LastName:   lastName,
		Email:      email,
		Department: department,
		HireDate:   hireDate,
	}

	// Decrypt sensitive fields based on role
	allowedFields := roleAccess[userRole]

	if contains(allowedFields, "phone") && phoneEncrypted.Valid {
		if decrypted, err := shared.DecryptAES256GCM(phoneEncrypted.String, encryptionKey); err == nil {
			emp.Phone = &decrypted
		}
	}

	if contains(allowedFields, "address") && addressEncrypted.Valid {
		if decrypted, err := shared.DecryptAES256GCM(addressEncrypted.String, encryptionKey); err == nil {
			emp.Address = &decrypted
		}
	}

	if contains(allowedFields, "salary") && salaryEncrypted.Valid {
		if decrypted, err := shared.DecryptAES256GCM(salaryEncrypted.String, encryptionKey); err == nil {
			emp.Salary = &decrypted
		}
	}

	response := map[string]interface{}{
		"employee":    emp,
		"status_code": 200,
	}

	body, _ := json.Marshal(response)
	return events.APIGatewayProxyResponse{
		StatusCode: 200,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}, nil
}

func connectDB() (*sql.DB, error) {
	dbHost := os.Getenv("DB_HOST")
	dbPort := os.Getenv("DB_PORT")
	dbName := os.Getenv("DB_NAME")
	dbUser := os.Getenv("DB_USER")
	dbPassword := os.Getenv("DB_PASSWORD")

	connStr := fmt.Sprintf("postgres://%s:%s@%s:%s/%s?sslmode=require",
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

func createErrorResponse(statusCode int, message string) events.APIGatewayProxyResponse {
	errorResp := ErrorResponse{
		Error:      message,
		StatusCode: statusCode,
	}

	body, _ := json.Marshal(errorResp)
	return events.APIGatewayProxyResponse{
		StatusCode: statusCode,
		Body:       string(body),
		Headers: map[string]string{
			"Content-Type": "application/json",
		},
	}
}

func contains(slice []string, item string) bool {
	for _, v := range slice {
		if v == item {
			return true
		}
	}
	return false
}

func main() {
	lambda.Start(handler)
}
