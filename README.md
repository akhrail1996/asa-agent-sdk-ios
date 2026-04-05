# ASA Agent SDK for iOS

Lightweight Apple Search Ads attribution and revenue tracking SDK. Links keyword-level ad attribution to in-app revenue, enabling ASA Agent to optimize bids based on actual LTV, not just installs.

## How It Works

1. **Attribution**: On first launch, the SDK collects an [AdServices](https://developer.apple.com/documentation/adservices) attribution token and sends it to the ASA Agent backend, which resolves it to get the exact keyword, campaign, and ad group that drove the install.

2. **Revenue Tracking**: When users make purchases, the SDK reports revenue events to ASA Agent. The backend joins revenue with attribution data to compute keyword-level LTV.

3. **Optimization**: ASA Agent uses this keyword → LTV mapping to automatically adjust bids — increasing spend on high-LTV keywords and reducing spend on underperformers.

No IDFA required. Works without ATT consent on iOS 14.3+.

## Requirements

- iOS 14.0+ (attribution requires iOS 14.3+)
- Swift 5.9+
- Xcode 15+

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/akhrail1996/asa-agent-sdk-ios.git", from: "0.7.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → paste the repo URL.

## Quick Start

### 1. Configure on App Launch

```swift
import ASAAgentSDK

@main
struct MyApp: App {
    init() {
        ASAAgent.configure(
            apiKey: "ask_your_api_key_here",  // From ASA Agent dashboard
            appId: "123456789"                 // Your App Store Adam ID
        )
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

### 2. Track Revenue

**Option A: Automatic (StoreKit 2, iOS 15+)**

```swift
// After configure(), enable auto-tracking:
if #available(iOS 15.0, *) {
    ASAAgent.enableAutoTracking()
}
```

This automatically captures all verified StoreKit 2 transactions.

**Option B: Manual**

```swift
// After a successful purchase:
ASAAgent.trackRevenue(
    productId: "com.yourapp.premium_monthly",
    revenue: 9.99,
    currency: "USD",
    type: .subscription,
    transactionId: "2000000123456789"
)
```

### 3. Get Your API Key

1. Go to your [ASA Agent dashboard](https://asaagent.xyz/dashboard/settings)
2. Navigate to **Settings → SDK Integration**
3. Click **Generate API Key** for your app
4. Copy the key (starts with `ask_`)

## API Reference

### `ASAAgent.configure(apiKey:appId:baseURL:loggingEnabled:)`

Initialize the SDK. Call once on app launch.

| Parameter | Type | Description |
|-----------|------|-------------|
| `apiKey` | `String` | Your SDK API key from the dashboard |
| `appId` | `String` | Your app's Adam ID (numeric App Store ID) |
| `baseURL` | `URL?` | Override API URL (for testing). Default: production |
| `loggingEnabled` | `Bool` | Enable debug logs. Default: `false` |

### `ASAAgent.trackRevenue(productId:revenue:currency:type:transactionId:)`

Report a revenue event.

| Parameter | Type | Description |
|-----------|------|-------------|
| `productId` | `String` | StoreKit product identifier |
| `revenue` | `Double` | Revenue amount |
| `currency` | `String` | ISO 4217 currency code |
| `type` | `RevenueEventType` | `.purchase`, `.subscription`, `.trial`, `.renewal`, `.refund` |
| `transactionId` | `String?` | StoreKit transaction ID (for deduplication) |

### `ASAAgent.enableAutoTracking()` (iOS 15+)

Automatically observe StoreKit 2 transactions and report revenue.

### `ASAAgent.retryAttribution()`

Manually retry attribution token collection (e.g., after network failure).

## Privacy

- **No IDFA collected**. The SDK does not use `ASIdentifierManager` or request ATT consent.
- **Anonymous device ID**: A random UUID stored in Keychain, not linked to any Apple identifier.
- **AdServices token**: An opaque, privacy-safe token provided by Apple. It contains no personal data.
- **Minimal data**: Only attribution + revenue events are sent. No user profiles, no tracking across apps.

## Architecture

```
App Launch
    │
    ├── SDK collects AdServices token (iOS 14.3+)
    │   └── Sends to ASA Agent backend
    │       └── Backend resolves token with Apple
    │           └── Gets: keywordId, campaignId, adGroupId, country
    │               └── Resolves names via Apple Search Ads API
    │                   └── Stores: device → keyword mapping
    │
    └── User makes purchase
        └── SDK reports revenue event
            └── Backend joins: device → keyword + revenue
                └── ASA Agent AI optimizes bids per keyword LTV
```

## License

MIT License. See [LICENSE](LICENSE) for details.
