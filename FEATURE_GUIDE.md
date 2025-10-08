# New Features Guide

## 1. Conditional Mock Responses

### Overview
Conditional mocks allow you to return different JSON responses based on request parameters. This is useful for testing different scenarios without changing your app code.

### Types of Conditional Matching

#### A. Query Parameter Matching
Match based on URL query parameters.

**Example Use Cases:**
- Different user profiles: `GET /api/user?id=1` vs `GET /api/user?id=2`
- Pagination: `GET /api/posts?page=1` vs `GET /api/posts?page=2`
- Filtering: `GET /api/products?category=electronics` vs `GET /api/products?category=books`

**How to Configure:**
1. Create or edit an endpoint
2. Set Mode to "Mock Response"
3. Enable "Use Conditional Mock" toggle
4. Tap "Conditional Mock(s)" card
5. Tap "+" to add a condition
6. Select "Query Parameter"
7. Enter:
    - Field Name: `id` (or any query param name)
    - Field Value: `1` (the value to match)
    - Mock Response: `{"id": 1, "name": "John"}`
8. Add more conditions as needed
9. Set a default mock response for non-matching requests

**Example Configuration:**
```
Endpoint: /api/user
Match Type: Exact
Mode: Mock Response
Use Conditional Mock: Yes

Conditional Mock 1:
  Type: Query Parameter
  Field Name: id
  Field Value: 1
  Response: {"id": 1, "name": "John Doe", "email": "john@example.com"}

Conditional Mock 2:
  Type: Query Parameter
  Field Name: id
  Field Value: 2
  Response: {"id": 2, "name": "Jane Smith", "email": "jane@example.com"}

Default Mock Response:
{"error": "User not found", "code": 404}
```

**Testing:**
```bash
curl "http://localhost:8080/api/user?id=1"  # Returns John Doe
curl "http://localhost:8080/api/user?id=2"  # Returns Jane Smith
curl "http://localhost:8080/api/user?id=99" # Returns error
```

#### B. Body Field Matching
Match based on JSON request body fields.

**Example Use Cases:**
- Different login responses: Based on username or userId
- Order processing: Different responses based on order type
- Payment methods: Different responses based on payment type

**How to Configure:**
1. Create or edit an endpoint
2. Set Mode to "Mock Response"
3. Enable "Use Conditional Mock" toggle
4. Tap "Conditional Mock(s)" card
5. Tap "+" to add a condition
6. Select "Body Field"
7. Enter:
    - Field Name: `userId` (or any body field name)
    - Field Value: `admin` (the value to match)
    - Mock Response: `{"token": "admin-token", "role": "admin"}`
8. Add more conditions as needed
9. Set a default mock response

**Example Configuration:**
```
Endpoint: /api/login
Match Type: Exact
Mode: Mock Response
Use Conditional Mock: Yes

Conditional Mock 1:
  Type: Body Field
  Field Name: userId
  Field Value: admin
  Response: {
    "token": "eyJhbGc...",
    "role": "admin",
    "permissions": ["read", "write", "delete"]
  }

Conditional Mock 2:
  Type: Body Field
  Field Name: userId
  Field Value: user
  Response: {
    "token": "eyJhbGc...",
    "role": "user",
    "permissions": ["read"]
  }

Default Mock Response:
{"error": "Invalid credentials", "code": 401}
```

**Testing:**
```bash
# Admin login
curl -X POST http://localhost:8080/api/login \
  -H "Content-Type: application/json" \
  -d '{"userId": "admin", "password": "secret"}'

# Regular user login
curl -X POST http://localhost:8080/api/login \
  -H "Content-Type: application/json" \
  -d '{"userId": "user", "password": "secret"}'
```

### Best Practices for Conditional Mocks

1. **Order Matters**: Conditions are evaluated in the order they appear
2. **Exact Matching**: Field values must match exactly (case-sensitive)
3. **Always Set Default**: Provide a default response for unmatched cases
4. **Test All Paths**: Verify each condition works as expected
5. **JSON Validation**: Ensure all mock responses are valid JSON

## 2. Auto Pass-Through

### Overview
Auto pass-through automatically forwards unmatched requests to a global base URL, eliminating the need to configure pass-through for every endpoint.

### How It Works

When auto pass-through is enabled:
1. Request comes to local server: `http://localhost:8080/api/users`
2. Server checks for matching endpoint configurations
3. If no match found → automatically forwards to: `{base_url}/api/users`
4. Response is returned to your app

### Configuration Steps

1. Go to Home Screen
2. Toggle "Auto Pass-Through" ON
3. Enter "Global Pass-Through Base URL"
    - Example: `https://api.staging.example.com`
    - Do NOT include trailing slash
4. Start the server

**Important:** You cannot change the base URL while the server is running. Stop the server first.

### Use Cases

#### Development Mode
```
Base URL: https://api.staging.example.com
Auto Pass-Through: Enabled

Configured Endpoints:
  - /api/login → Mock (testing different scenarios)
  - /api/users/profile → Mock (testing UI changes)

All other requests automatically forwarded:
  - /api/products → https://api.staging.example.com/api/products
  - /api/orders → https://api.staging.example.com/api/orders
  - /api/notifications → https://api.staging.example.com/api/notifications
```

#### Hybrid Testing
```
Base URL: https://api.production.example.com
Auto Pass-Through: Enabled

Mock only problematic endpoints:
  - /api/payments → Mock (test failure scenarios)
  - /api/external-service → Mock (external service is down)

Everything else uses real API:
  - /api/users → Real API
  - /api/products → Real API
  - /api/dashboard → Real API
```

#### API Migration Testing
```
Base URL: https://api-v2.example.com
Auto Pass-Through: Enabled

Mock deprecated endpoints for compatibility:
  - /api/v1/old-endpoint → Mock (return v2 format)

New endpoints use v2 API automatically:
  - /api/v2/users → Auto-forwarded
  - /api/v2/products → Auto-forwarded
```

### Path Handling

The auto pass-through preserves the full request path:

```
Request: localhost:8080/api/v1/users/123/orders?status=pending
Base URL: https://api.example.com

Result: https://api.example.com/api/v1/users/123/orders?status=pending
```

### Priority Order

1. **Exact Match Endpoints** (highest priority)
2. **Wildcard/Regex Endpoints**
3. **Auto Pass-Through** (lowest priority)

### Best Practices

1. **Use for Development**: Great for switching between local mocks and staging/production APIs
2. **Minimize Mocks**: Only mock what you need to test, let everything else pass through
3. **Secure URLs**: Only use HTTPS URLs for production/staging APIs
4. **Monitor Logs**: Check the logs to see which requests are being forwarded
5. **Test Connectivity**: Ensure the base URL is accessible before enabling

### Troubleshooting

**Issue**: Requests not being forwarded
- Check that auto pass-through toggle is enabled
- Verify the base URL is correct (no trailing slash)
- Ensure no endpoint pattern matches the request
- Check logs for error messages

**Issue**: SSL/Certificate errors
- Ensure base URL uses HTTPS
- Verify the remote server's SSL certificate is valid

**Issue**: Performance issues
- Auto pass-through adds network latency
- Consider mocking frequently called endpoints
- Use mock mode for offline development

## 3. Combining Both Features

### Advanced Scenario: User Role Testing

```
Auto Pass-Through: Enabled
Base URL: https://api.example.com

Endpoint 1: /api/auth/login
  Mode: Mock Response
  Use Conditional Mock: Yes
  
  Condition 1 (Query Param):
    Field: role
    Value: admin
    Response: {"token": "admin-token", "role": "admin"}
  
  Condition 2 (Query Param):
    Field: role
    Value: user
    Response: {"token": "user-token", "role": "user"}

Endpoint 2: /api/profile
  Mode: Mock Response
  Use Conditional Mock: Yes
  
  Condition 1 (Body Field):
    Field: userId
    Value: 1
    Response: {"id": 1, "name": "Admin User", "permissions": ["all"]}
  
  Condition 2 (Body Field):
    Field: userId
    Value: 2
    Response: {"id": 2, "name": "Regular User", "permissions": ["read"]}

All other endpoints automatically forwarded to real API.
```

### Testing Flow:
1. Login with different roles → Mocked with conditional responses
2. Fetch user profile → Mocked with conditional responses
3. Fetch products, orders, etc. → Auto-forwarded to real API

This gives you full control over authentication testing while using real API for everything else!

## Summary

- **Conditional Mocks**: Return different responses based on request parameters
    - Query parameters for GET requests
    - Body fields for POST/PUT requests

- **Auto Pass-Through**: Automatically forward unmatched requests
    - Configure once, applies to all unmatched endpoints
    - Perfect for hybrid mock/real API testing

Both features work together to give you maximum flexibility in testing!