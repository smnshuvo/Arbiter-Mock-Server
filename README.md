## Tips

1. **Testing Different User Scenarios**: Use conditional mocks to test different user types (admin, user, guest) without changing your app code
2. **Query Parameter Testing**: Test pagination, filtering, and sorting by setting up conditional mocks based on query parameters
3. **Body Field Testing**: Test different authentication flows or request variations using body field conditional mocks
4. **Auto Pass-Through for Development**: Enable auto pass-through with your staging API as the base URL, then only mock specific problematic endpoints
5. **Delay Testing**: Add delays to mock responses to test loading states and timeout handling
6. **Error Testing**: Create mock endpoints with 4xx/5xx status codes to test error handling
7. **Offline Mode**: Use mock mode to develop without internet connection
8. **API Versioning**: Test different API versions by switching between mock and pass-through
9. **Mixed Mode**: Use some endpoints in mock mode and others in pass-through mode for hybrid testing
10. **Conditional Priority**: Conditional mocks are checked in order - organize them from most specific to least specific

## Troubleshooting

### Database Migration
If you're upgrading from an older version, you may need to:
1. Clear app data (Settings → Apps → Network Interceptor → Clear Data)
2. Or manually run: `flutter pub run build_runner build --delete-conflicting-outputs`

### Conditional Mocks Not Working
- Ensure "Use Conditional Mock" is enabled
- Check that field names match exactly (case-sensitive)
- Verify JSON syntax in mock responses
- Test query parameters with exact URL format: `localhost:8080/path?param=value`

### Auto Pass-Through Not Working
- Verify the global pass-through URL is set correctly
- Ensure auto pass-through toggle is enabled
- Check that the base URL doesn't have a trailing slash (it's added automatically)
- Make sure no endpoint pattern matches the request (matched endpoints have priority)

## License

This project is for development and testing purposes.# Network Interceptor

A Flutter application for intercepting and mocking network requests during development and testing.

## Features

- **Local HTTP Server**: Run a local proxy server on your device
- **Request Interception**: Capture and intercept HTTP requests
- **Mock Responses**: Return predefined JSON responses with configurable delays
- **Conditional Mocks**: Return different responses based on query parameters or request body fields
- **Auto Pass-Through**: Automatically forward unmatched requests to a global base URL
- **Pass-Through Mode**: Forward requests to actual HTTPS servers
- **Request Logging**: View detailed logs of all intercepted requests
- **Advanced Filtering**: Filter logs by method, status code, type, and date range
- **Search Functionality**: Search logs by URL or method
- **Import/Export**: Share endpoint configurations across devices
- **Clean Architecture**: Built with SOLID principles and clean architecture

## Architecture

The project follows Clean Architecture principles with three main layers:

### Domain Layer
- **Entities**: Core business objects (Endpoint, RequestLog)
- **Repositories**: Abstract interfaces for data operations
- **Use Cases**: Business logic implementation

### Data Layer
- **Models**: Data transfer objects with JSON serialization
- **Data Sources**: Local database (SQLite) and HTTP server implementation
- **Repository Implementations**: Concrete implementations of domain repositories

### Presentation Layer
- **BLoC**: State management using flutter_bloc
- **Pages**: UI screens
- **Widgets**: Reusable UI components

## Setup

1. **Install Dependencies**
   ```bash
   flutter pub get
   ```

2. **Generate Code**
   ```bash
   flutter pub run build_runner build --delete-conflicting-outputs
   ```

3. **Run the App**
   ```bash
   flutter run
   ```

## Usage

### 1. Start the Server

- Open the app
- Configure the port (default: 8080)
- Tap "Start Server"
- The server URL will be displayed (e.g., `http://localhost:8080`)

### 2. Configure Endpoints

- Tap "Manage Endpoints"
- Tap the "+" button to add a new endpoint
- Configure:
    - **URL Pattern**: The endpoint path (e.g., `/api/users`)
    - **Match Type**:
        - Exact: Exact path match
        - Wildcard: Use `*` for wildcards (e.g., `/api/*`)
        - Regex: Use regular expressions
    - **Mode**:
        - Mock Response: Return predefined JSON
        - Pass Through: Forward to actual server
    - **Mock Response**: JSON to return (if Mock mode)
    - **Conditional Mocks**: Return different responses based on conditions
        - Query Parameter: Match based on URL query params (e.g., `?id=1`)
        - Body Field: Match based on request body fields (e.g., `{"userId": "123"}`)
    - **Response Delay**: Delay in milliseconds (if Mock mode)
    - **Target URL**: HTTPS URL to forward to (if Pass Through mode)

### 2.1. Configure Auto Pass-Through

On the home screen:
- Enable "Auto Pass-Through" toggle
- Set a "Global Pass-Through Base URL" (e.g., `https://api.example.com`)
- When enabled, any request that doesn't match a configured endpoint will automatically be forwarded to: `base_url + request_path`
- Example: Request to `localhost:8080/api/users` → Forwarded to `https://api.example.com/api/users`

### 3. Use in Your App

In your Flutter app that you want to debug:

```dart
// Change your base URL to the local server
const String baseUrl = 'http://localhost:8080';

// Or use conditional configuration
const String baseUrl = kDebugMode 
    ? 'http://localhost:8080' 
    : 'https://api.production.com';
```

### 4. View Logs

- Tap "View Logs" from the home screen
- View all intercepted requests with details
- Use search to find specific requests
- Apply filters for:
    - HTTP methods (GET, POST, etc.)
    - Status codes (2xx, 4xx, 5xx)
    - Log types (Mock vs Pass-through)
    - Date ranges
- Tap on any log to expand and view full details

### 5. Import/Export Configurations

**Export:**
- Go to "Manage Endpoints"
- Tap the export icon (download)
- Share the JSON file

**Import:**
- Go to "Manage Endpoints"
- Tap the import icon (upload)
- Select a JSON file
- All endpoints will be imported

## Example Endpoint Configurations

### Mock Response Example
```
Pattern: /api/users
Match Type: Exact
Mode: Mock Response
Mock Response:
{
  "users": [
    {"id": 1, "name": "John Doe"},
    {"id": 2, "name": "Jane Smith"}
  ]
}
Delay: 500ms
```

### Conditional Mock Example (Query Parameter)
```
Pattern: /api/user
Match Type: Exact
Mode: Mock Response
Use Conditional Mock: Enabled

Condition 1:
  Type: Query Parameter
  Field Name: id
  Field Value: 1
  Response: {"id": 1, "name": "John Doe", "role": "admin"}

Condition 2:
  Type: Query Parameter
  Field Name: id
  Field Value: 2
  Response: {"id": 2, "name": "Jane Smith", "role": "user"}

Default Response: {"error": "User not found"}

Usage:
  localhost:8080/api/user?id=1 → Returns John Doe
  localhost:8080/api/user?id=2 → Returns Jane Smith
  localhost:8080/api/user?id=3 → Returns error
```

### Conditional Mock Example (Body Field)
```
Pattern: /api/login
Match Type: Exact
Mode: Mock Response
Use Conditional Mock: Enabled

Condition 1:
  Type: Body Field
  Field Name: userId
  Field Value: admin
  Response: {"token": "admin-token-123", "role": "admin"}

Condition 2:
  Type: Body Field
  Field Name: userId
  Field Value: user
  Response: {"token": "user-token-456", "role": "user"}

Default Response: {"error": "Invalid credentials"}

Usage:
  POST localhost:8080/api/login
  Body: {"userId": "admin", "password": "***"}
  → Returns admin token
```

### Pass-Through Example
```
Pattern: /api/posts
Match Type: Exact
Mode: Pass Through
Target URL: https://jsonplaceholder.typicode.com/posts
```

### Wildcard Example
```
Pattern: /api/v1/*
Match Type: Wildcard
Mode: Pass Through
Target URL: https://api.example.com/api/v1/
```

### Auto Pass-Through Example
```
Global Pass-Through Base URL: https://api.example.com
Auto Pass-Through: Enabled

Any unmatched request:
  localhost:8080/api/products → https://api.example.com/api/products
  localhost:8080/api/orders/123 → https://api.example.com/api/orders/123
  localhost:8080/v2/users → https://api.example.com/v2/users
```

## Dependencies

- `flutter_bloc`: State management
- `shelf`: HTTP server
- `sqflite`: Local database
- `http`: HTTP client for pass-through
- `file_picker`: File selection for import
- `share_plus`: Sharing export files
- `get_it`: Dependency injection
- `equatable`: Value equality
- `intl`: Date formatting

## Project Structure

```
lib/
├── data/
│   ├── datasources/
│   │   ├── local/
│   │   │   ├── database_helper.dart
│   │   │   ├── endpoint_local_datasource.dart
│   │   │   └── log_local_datasource.dart
│   │   └── server/
│   │       └── http_server_service.dart
│   ├── models/
│   │   ├── endpoint_model.dart
│   │   └── request_log_model.dart
│   └── repositories/
│       ├── endpoint_repository_impl.dart
│       ├── log_repository_impl.dart
│       └── server_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── endpoint.dart
│   │   └── request_log.dart
│   ├── repositories/
│   │   ├── endpoint_repository.dart
│   │   ├── log_repository.dart
│   │   └── server_repository.dart
│   └── usecases/
│       ├── endpoint_usecases.dart
│       ├── log_usecases.dart
│       └── server_usecases.dart
├── presentation/
│   ├── bloc/
│   │   ├── endpoint/
│   │   │   └── endpoint_bloc.dart
│   │   ├── log/
│   │   │   └── log_bloc.dart
│   │   └── server/
│   │       └── server_bloc.dart
│   └── pages/
│       ├── home_screen.dart
│       ├── endpoints_screen.dart
│       ├── endpoint_form_screen.dart
│       ├── logs_screen.dart
│       └── log_filter_screen.dart
├── injection_container.dart
└── main.dart
```

## Tips

1. **Testing**: Use this app alongside your development app to test different API responses
2. **Delay Testing**: Add delays to mock responses to test loading states
3. **Error Testing**: Create mock endpoints with 4xx/5xx status codes to test error handling
4. **Offline Mode**: Use mock mode to develop without internet connection
5. **API Versioning**: Test different API versions by switching between mock and pass-through

## License

This project is for development and testing purposes.