# Changelog

## Version 2.0.0 - New Features Added

### 🎉 Major Features
#### 0. Dark Mode Added
- Thanks to @dipta-2707

#### 1. Conditional Mock Responses
Return different JSON responses based on request conditions:

**Query Parameter Matching:**
- Match based on URL query parameters
- Example: `?id=1` returns different data than `?id=2`
- Perfect for testing pagination, filtering, user profiles

**Body Field Matching:**
- Match based on JSON request body fields
- Example: Different responses based on `userId` or `orderType`
- Perfect for testing login flows, role-based responses

**Features:**
- Multiple conditions per endpoint
- Default fallback response
- Visual indicator showing condition count
- Easy-to-use configuration UI

#### 2. Auto Pass-Through Mode
Automatically forward unmatched requests to a global base URL:

**How it works:**
- Set a global base URL once
- Any request without a matching endpoint gets forwarded automatically
- Request path is preserved: `localhost:8080/api/users` → `{base_url}/api/users`

**Benefits:**
- No need to configure pass-through for every endpoint
- Perfect for hybrid testing (mock some, real API for others)
- Quick switch between development and production APIs
- Ideal for API migration testing

**Configuration:**
- Global toggle on home screen
- Configure base URL once
- Enable/disable anytime
- Works alongside existing endpoints

### 📊 Database Changes
- Added `conditionalMocksJson` field to store conditional mock rules
- Added `useConditionalMock` flag for endpoints
- Backward compatible with existing data

### 🎨 UI Improvements
- New "Auto Pass-Through" section on home screen
- Conditional mock configuration screen
- Visual indicators for conditional mocks on endpoint list
- Improved endpoint form with conditional mock toggle
- Better visual feedback for enabled features

### 🔧 Technical Changes
- Enhanced HTTP server to support conditional matching
- Added query parameter parsing
- Added request body field extraction
- Improved pass-through logic with auto-forwarding
- New use cases for server configuration
- Updated BLoC for new features

### 📝 Documentation
- Added comprehensive FEATURE_GUIDE.md
- Updated README.md with new examples
- Added troubleshooting section
- Included best practices

### 🐛 Bug Fixes
- Improved error handling in conditional mock parsing
- Fixed JSON parsing for nested body fields
- Better error messages for configuration issues

---

## Version 1.0.0 - Initial Release

### Features
- Local HTTP server
- Endpoint configuration with exact/wildcard/regex matching
- Mock responses with configurable delays
- Pass-through mode to forward requests
- Request logging with detailed information
- Advanced filtering and search
- Import/Export configurations
- Clean architecture implementation