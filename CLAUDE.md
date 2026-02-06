# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Concierge (display name: "StayMate") is a tvOS vacation rental property management app for Apple TV. It serves as a digital concierge for guests at Kiawah Island vacation properties, providing WiFi credentials, local recommendations, weather/tide data, streaming app access, and property instructions.

## Build Commands

```bash
# Open in Xcode
open Concierge.xcodeproj

# Build from command line
xcodebuild -project Concierge.xcodeproj -scheme Concierge -configuration Release

# Run on Apple TV simulator
xcodebuild -project Concierge.xcodeproj -scheme Concierge -destination 'platform=tvOS Simulator,name=Apple TV'
```

## Tech Stack

- **Swift 5.0 / SwiftUI** - tvOS 26.2+
- **Combine** - Reactive state management
- **No external dependencies** - Uses only Apple native frameworks

## Architecture

The app follows MVVM but is currently monolithic - all code lives in `Concierge/ContentView.swift` (~1,400 lines):

- **Lines 14-99**: Data models (`LocalRecommendation`, `RentalDataResponse`, `ForecastDay`, `TideEvent`, etc.)
- **Lines 112-408**: `RentalViewModel` - Single ObservableObject managing all state and API calls
- **Lines 414-1411**: SwiftUI views (`KiawahConciergeView`, `SettleInView`, `StreamingAppsView`, etc.)

### Key Data Flow

`RentalViewModel.fetchAllData()` uses Swift concurrency TaskGroup to fetch in parallel:
1. **n8n webhook** - Property data (guest name, WiFi, places, images)
2. **OpenWeatherMap API** - 5-day weather forecast
3. **Sunrise-Sunset.org** - Sun times
4. **NOAA Tides API** - Tide predictions (station 8667062)

### External Service Dependencies

- n8n webhook at `n8n.srv1321920.hstgr.cloud`
- OpenWeatherMap (API key embedded in source)
- NOAA Tides & Currents API
- QR Server API for WiFi QR codes

## n8n Workflow API Access

Claude Code can view and update n8n workflows using the API:

- **Base URL:** `https://n8n.srv1321920.hstgr.cloud/api/v1`
- **API Key:** `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJlNWY2NmNhMC1jNWFmLTRiYjItODA1Ni1mNWU2ODU5Yjc3ZWQiLCJpc3MiOiJuOG4iLCJhdWQiOiJwdWJsaWMtYXBpIiwiaWF0IjoxNzcwMzc4Nzg0LCJleHAiOjE3NzI5MjQ0MDB9._Cjs604AmRWlpfJaO4DNAswvS02BVfouL1wK1R0CWEE`
- **Active Workflow ID:** `kOFnHIgALKRsK5Z-eSvtL` (Concierge Apple TV)

Example usage:
```bash
curl -X GET "https://n8n.srv1321920.hstgr.cloud/api/v1/workflows" \
  -H "X-N8N-API-KEY: <api_key>"
```

## tvOS Considerations

- Design for TV remote navigation with large touch targets
- Use `@FocusState` for focus management
- LazyVGrid for efficient list rendering
- Ultra-thin material backgrounds for TV aesthetic
- Hardcoded location: Kiawah Island (32.6082°N, -80.0848°W)
