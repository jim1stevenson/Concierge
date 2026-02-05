import SwiftUI
import Combine

@main
struct KiawahRentalApp: App {
    var body: some Scene {
        WindowGroup {
            KiawahConciergeView()
        }
    }
}

// =============================================================
// MARK: - 1. DATA MODELS
// =============================================================

struct LocalRecommendation: Identifiable, Codable, Hashable {
    let id = UUID()
    let name: String
    let type: String?
    let description: String
    let address: String
    let imageURL: String
    
    enum CodingKeys: String, CodingKey {
        case name, type, description, address, imageURL
    }
}

struct RentalDataResponse: Codable {
    let guestName: String
    let heroImage: String
    let wifiSSID: String
    let wifiPass: String
    let places: [LocalRecommendation]
    let dining: DiningSection?
}

struct PlaceCategory: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let icon: String
    let places: [LocalRecommendation]
    
    var coverImageURL: String {
        places.first?.imageURL ?? ""
    }
    
    static func iconFor(_ category: String) -> String {
        switch category.lowercased() {
        case "dining": return "fork.knife"
        case "activities": return "figure.hiking"
        case "golf": return "figure.golf"
        case "shopping": return "bag.fill"
        case "medical": return "cross.case.fill"
        default: return "mappin.circle.fill"
        }
    }
}

// --- Weather & Environment Models ---

struct ForecastDay: Identifiable {
    let id = UUID()
    let date: Date
    let high: Int
    let low: Int
    let icon: String
    let condition: String
    let precipChance: Int
    let sunrise: String
    let sunset: String
}

struct HourlyForecast: Identifiable {
    let id = UUID()
    let time: Date
    let temp: Int
    let icon: String
    let condition: String
    let precipChance: Int
}

struct MoonPhase {
    let phase: Double      // 0.0 to 1.0 (0=new, 0.5=full)
    let name: String       // "New Moon", "Waxing Crescent", etc.
    let icon: String       // SF Symbol name
}

struct SunTimes {
    let sunrise: String
    let sunset: String
}

struct TideEvent: Identifiable {
    let id = UUID()
    let time: String
    let type: String
    let height: String
}

struct SettleInCard: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let content: String
}

struct HowDoICard: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let icon: String
    let instructions: String
}

// --- Dining Models (Rich Data) ---

struct GoogleReview: Identifiable, Codable, Hashable {
    var id: String { "\(authorName)-\(rating)" }
    let authorName: String
    let authorPhoto: String?
    let rating: Int
    let text: String
    let relativeTime: String

    enum CodingKeys: String, CodingKey {
        case authorName = "author_name"
        case authorPhoto = "author_photo"
        case rating, text
        case relativeTime = "relative_time"
    }
}

struct DiningVenue: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let location: String
    let cuisines: [String]
    let price: String
    let mealTimes: [String]
    let shortDescription: String
    let heroImage: String
    let logoImage: String
    let hours: String
    let reservationRequired: Bool?
    let reservationPhone: String
    let attire: String

    // Google Places review data (optional)
    let googleRating: Double?
    let googleReviewCount: Int?
    let googleReviews: [GoogleReview]?
}

struct DiningSection: Codable {
    let title: String
    let intro: String
    let heroImage: String
    let venues: [DiningVenue]
}

// =============================================================
// MARK: - 2. THE DATA ENGINE
// =============================================================

class RentalViewModel: ObservableObject {
    @Published var guestName: String = "Guest"
    @Published var heroImageURL: String = ""
    @Published var heroImage: UIImage? = nil
    @Published var wifiSSID: String = ""
    @Published var wifiPass: String = ""
    @Published var recommendations: [LocalRecommendation] = []
    @Published var categories: [PlaceCategory] = []
    @Published var diningSection: DiningSection? = nil

    @Published var forecast: [ForecastDay] = []
    @Published var hourlyForecast: [HourlyForecast] = []
    @Published var currentTemp: Int = 0
    @Published var currentLow: Int = 0
    @Published var currentCondition: String = ""
    @Published var currentIcon: String = "cloud.fill"
    @Published var sunTimes: SunTimes = SunTimes(sunrise: "--", sunset: "--")
    @Published var moonPhase: MoonPhase = MoonPhase(phase: 0, name: "—", icon: "moon.fill")
    @Published var tideEvents: [TideEvent] = []
    
    @Published var settleInCards: [SettleInCard] = []
    
    private let lat = 32.6082
    private let lon = -80.0848
    private let noaaStation = "8667062"
    
    // MARK: - Fetch All Data
    func fetchAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRentalData() }
            group.addTask { await self.fetchWeather() }
            group.addTask { await self.fetchTides() }
        }
    }
    
    // MARK: - Rental Data from n8n
    func fetchRentalData() async {
        guard let url = URL(string: "https://n8n.srv1321920.hstgr.cloud/webhook/kiawah-data") else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let decoded = try decoder.decode(RentalDataResponse.self, from: data)
            
            var downloadedImage: UIImage? = nil
            if let imageURL = URL(string: decoded.heroImage) {
                let (imageData, _) = try await URLSession.shared.data(from: imageURL)
                downloadedImage = UIImage(data: imageData)
            }
            
            let grouped = Dictionary(grouping: decoded.places, by: { $0.type ?? "Other" })
            let categoryOrder = ["Dining", "Activities", "Golf", "Shopping", "Medical"]
            
            let sortedCategories = categoryOrder.compactMap { catName -> PlaceCategory? in
                let match = grouped.first(where: { $0.key.lowercased() == catName.lowercased() })
                guard let places = match?.value, !places.isEmpty else { return nil }
                return PlaceCategory(name: catName, icon: PlaceCategory.iconFor(catName), places: places)
            }
            
            let knownNames = Set(categoryOrder.map { $0.lowercased() })
            let extraCategories = grouped
                .filter { !knownNames.contains($0.key.lowercased()) }
                .map { PlaceCategory(name: $0.key, icon: PlaceCategory.iconFor($0.key), places: $0.value) }
            
            let cards = [
                SettleInCard(title: "Check Out Instructions", icon: "door.right.hand.open",
                             content: "Check out by 10 AM. Please strip all beds and start the dishwasher. Take trash to the bins at the end of the driveway. Leave keys on the kitchen counter."),
                SettleInCard(title: "Emergency Info", icon: "phone.fill",
                             content: "Property Manager: (843) 555-1234\nAfter Hours Emergency: (843) 555-5678\nKiawah Island Security: (843) 768-5566\nAlarm Code: 1234"),
                SettleInCard(title: "Parking & Gate Code", icon: "car.fill",
                             content: "Main Gate Code: #4521\nPark in the driveway only — max 2 vehicles.\nGuest passes available at the gate house for visitors."),
                SettleInCard(title: "Trash & Recycling", icon: "trash.fill",
                             content: "Trash pickup is Tuesday morning. Bins are in the garage — roll them to the curb by 7 AM Monday night.\nBlue bin: recycling. Green bin: trash.\nNo glass in recycling."),
                SettleInCard(title: "Pool & Hot Tub", icon: "figure.pool.swim",
                             content: "Pool hours: 8 AM – 10 PM\nHot tub: replace cover after each use.\nHeater controls are on the back wall panel near the outdoor shower.\nNo glass near the pool area.")
            ]
            
            await MainActor.run { [downloadedImage] in
                self.guestName = decoded.guestName
                self.heroImageURL = decoded.heroImage
                self.heroImage = downloadedImage
                self.wifiSSID = decoded.wifiSSID
                self.wifiPass = decoded.wifiPass
                self.recommendations = decoded.places
                self.categories = sortedCategories + extraCategories
                self.settleInCards = cards
                self.diningSection = decoded.dining
            }
        } catch {
            print("❌ Decode Error: \(error)")
        }
    }
    
    // MARK: - Weather (Open-Meteo API)
    func fetchWeather() async {
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lat)&longitude=\(lon)&current=temperature_2m,weather_code,is_day&hourly=temperature_2m,weather_code,precipitation_probability&daily=temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,sunrise,sunset&temperature_unit=fahrenheit&timezone=America/New_York&forecast_days=7"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

            // Parse current conditions
            let currentTemperature: Int
            let currentWeatherCode: Int
            let isDay: Bool
            if let current = json["current"] as? [String: Any] {
                currentTemperature = Int((current["temperature_2m"] as? Double ?? 0).rounded())
                currentWeatherCode = current["weather_code"] as? Int ?? 0
                isDay = (current["is_day"] as? Int ?? 1) == 1
            } else {
                currentTemperature = 0
                currentWeatherCode = 0
                isDay = true
            }

            // Parse daily forecast
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"

            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            timeFormatter.timeZone = TimeZone(identifier: "America/New_York")

            let displayTimeFormatter = DateFormatter()
            displayTimeFormatter.dateFormat = "h:mm a"
            displayTimeFormatter.timeZone = TimeZone(identifier: "America/New_York")

            var forecastDays: [ForecastDay] = []
            var firstDaySunrise = "--"
            var firstDaySunset = "--"

            if let daily = json["daily"] as? [String: Any],
               let times = daily["time"] as? [String],
               let highs = daily["temperature_2m_max"] as? [Double],
               let lows = daily["temperature_2m_min"] as? [Double],
               let codes = daily["weather_code"] as? [Int],
               let precipChances = daily["precipitation_probability_max"] as? [Int],
               let sunrises = daily["sunrise"] as? [String],
               let sunsets = daily["sunset"] as? [String] {

                for i in 0..<min(7, times.count) {
                    guard let date = dayFormatter.date(from: times[i]) else { continue }

                    // Format sunrise/sunset times
                    var sunriseDisplay = sunrises[i]
                    var sunsetDisplay = sunsets[i]
                    if let sunriseDate = timeFormatter.date(from: sunrises[i]) {
                        sunriseDisplay = displayTimeFormatter.string(from: sunriseDate)
                    }
                    if let sunsetDate = timeFormatter.date(from: sunsets[i]) {
                        sunsetDisplay = displayTimeFormatter.string(from: sunsetDate)
                    }

                    if i == 0 {
                        firstDaySunrise = sunriseDisplay
                        firstDaySunset = sunsetDisplay
                    }

                    forecastDays.append(ForecastDay(
                        date: date,
                        high: Int(highs[i].rounded()),
                        low: Int(lows[i].rounded()),
                        icon: Self.sfSymbolForWMO(codes[i], isDay: true),
                        condition: Self.conditionTextForWMO(codes[i]),
                        precipChance: precipChances[i],
                        sunrise: sunriseDisplay,
                        sunset: sunsetDisplay
                    ))
                }
            }

            // Parse hourly forecast (next 24 hours)
            let hourlyFormatter = ISO8601DateFormatter()
            hourlyFormatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]

            var hourlyData: [HourlyForecast] = []
            if let hourly = json["hourly"] as? [String: Any],
               let times = hourly["time"] as? [String],
               let temps = hourly["temperature_2m"] as? [Double],
               let codes = hourly["weather_code"] as? [Int],
               let precipChances = hourly["precipitation_probability"] as? [Int] {

                let now = Date()
                let calendar = Calendar.current
                var count = 0

                for i in 0..<times.count where count < 8 {
                    // Parse time in local timezone format from Open-Meteo
                    let timeStr = times[i]
                    guard let time = timeFormatter.date(from: timeStr) else { continue }

                    // Skip past hours
                    if time < now && !calendar.isDate(time, equalTo: now, toGranularity: .hour) {
                        continue
                    }

                    let hour = calendar.component(.hour, from: time)
                    let hourIsDay = hour >= 6 && hour < 20

                    hourlyData.append(HourlyForecast(
                        time: time,
                        temp: Int(temps[i].rounded()),
                        icon: Self.sfSymbolForWMO(codes[i], isDay: hourIsDay),
                        condition: Self.conditionTextForWMO(codes[i]),
                        precipChance: precipChances[i]
                    ))
                    count += 1
                }
            }

            // Calculate moon phase for today
            let todayMoonPhase = calculateMoonPhase(for: Date())

            let finalForecast = forecastDays
            let finalHourly = hourlyData
            let finalSunrise = firstDaySunrise
            let finalSunset = firstDaySunset
            let finalCurrentTemp = currentTemperature
            let finalCurrentWeatherCode = currentWeatherCode
            let finalIsDay = isDay

            await MainActor.run {
                self.forecast = finalForecast
                self.hourlyForecast = finalHourly
                self.currentTemp = finalCurrentTemp
                self.currentLow = finalForecast.first?.low ?? 0
                self.currentCondition = Self.conditionTextForWMO(finalCurrentWeatherCode)
                self.currentIcon = Self.sfSymbolForWMO(finalCurrentWeatherCode, isDay: finalIsDay)
                self.sunTimes = SunTimes(sunrise: finalSunrise, sunset: finalSunset)
                self.moonPhase = todayMoonPhase
            }
        } catch {
            print("❌ Weather Error: \(error)")
        }
    }
    
    // MARK: - NOAA Tides
    func fetchTides() async {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let today = dateFormatter.string(from: Date())
        
        let urlString = "https://api.tidesandcurrents.noaa.gov/api/prod/datagetter?begin_date=\(today)&end_date=\(today)&station=\(noaaStation)&product=predictions&datum=MLLW&time_zone=lst_ldt&interval=hilo&units=english&format=json&application=KiawahConcierge"
        guard let url = URL(string: urlString) else {
            print("❌ Tide Error: Bad URL")
            return
        }
        
        print("🌊 Fetching tides from: \(urlString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("🌊 Tide API status: \(httpResponse.statusCode)")
            }
            
            if let rawString = String(data: data, encoding: .utf8) {
                print("🌊 Tide raw response: \(rawString.prefix(500))")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("❌ Tide Error: Could not parse JSON")
                return
            }
            
            guard let predictions = json["predictions"] as? [[String: Any]] else {
                if let error = json["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    print("❌ NOAA Error: \(message)")
                }
                print("❌ Tide Error: No predictions key in response. Keys: \(json.keys)")
                return
            }
            
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd HH:mm"
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            
            var events: [TideEvent] = []
            for pred in predictions {
                guard let t = pred["t"] as? String,
                      let v = pred["v"] as? String,
                      let type = pred["type"] as? String else { continue }
                
                let displayTime: String
                if let date = timeFormatter.date(from: t) {
                    displayTime = displayFormatter.string(from: date)
                } else {
                    displayTime = t
                }
                
                events.append(TideEvent(
                    time: displayTime,
                    type: type == "H" ? "High" : "Low",
                    height: String(format: "%.1f ft", Double(v) ?? 0)
                ))
            }
            
            print("🌊 Parsed \(events.count) tide events")
            
            await MainActor.run { [events] in
                self.tideEvents = events
            }
        } catch {
            print("❌ Tide Error: \(error)")
        }
    }
    
    // MARK: - OpenWeather icon to SF Symbol (legacy, kept for reference)
    static func sfSymbol(for owIcon: String) -> String {
        switch owIcon {
        case "01d": return "sun.max.fill"
        case "01n": return "moon.fill"
        case "02d": return "cloud.sun.fill"
        case "02n": return "cloud.moon.fill"
        case "03d", "03n": return "cloud.fill"
        case "04d", "04n": return "smoke.fill"
        case "09d", "09n": return "cloud.drizzle.fill"
        case "10d": return "cloud.sun.rain.fill"
        case "10n": return "cloud.moon.rain.fill"
        case "11d", "11n": return "cloud.bolt.fill"
        case "13d", "13n": return "snowflake"
        case "50d", "50n": return "cloud.fog.fill"
        default: return "cloud.fill"
        }
    }

    // MARK: - WMO Weather Code to SF Symbol (Open-Meteo)
    static func sfSymbolForWMO(_ code: Int, isDay: Bool) -> String {
        switch code {
        case 0:  // Clear sky
            return isDay ? "sun.max.fill" : "moon.fill"
        case 1:  // Mainly clear
            return isDay ? "sun.max.fill" : "moon.fill"
        case 2:  // Partly cloudy
            return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3:  // Overcast
            return "cloud.fill"
        case 45, 48:  // Fog
            return "cloud.fog.fill"
        case 51, 53, 55:  // Drizzle
            return "cloud.drizzle.fill"
        case 56, 57:  // Freezing drizzle
            return "cloud.sleet.fill"
        case 61, 63, 65:  // Rain
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 66, 67:  // Freezing rain
            return "cloud.sleet.fill"
        case 71, 73, 75:  // Snowfall
            return "snowflake"
        case 77:  // Snow grains
            return "snowflake"
        case 80, 81, 82:  // Rain showers
            return isDay ? "cloud.sun.rain.fill" : "cloud.moon.rain.fill"
        case 85, 86:  // Snow showers
            return "cloud.snow.fill"
        case 95:  // Thunderstorm
            return "cloud.bolt.fill"
        case 96, 99:  // Thunderstorm with hail
            return "cloud.bolt.rain.fill"
        default:
            return "cloud.fill"
        }
    }

    // MARK: - WMO Weather Code to Condition Text
    static func conditionTextForWMO(_ code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1: return "Mostly Clear"
        case 2: return "Partly Cloudy"
        case 3: return "Overcast"
        case 45: return "Fog"
        case 48: return "Icy Fog"
        case 51: return "Light Drizzle"
        case 53: return "Drizzle"
        case 55: return "Heavy Drizzle"
        case 56, 57: return "Freezing Drizzle"
        case 61: return "Light Rain"
        case 63: return "Rain"
        case 65: return "Heavy Rain"
        case 66, 67: return "Freezing Rain"
        case 71: return "Light Snow"
        case 73: return "Snow"
        case 75: return "Heavy Snow"
        case 77: return "Snow Grains"
        case 80: return "Light Showers"
        case 81: return "Showers"
        case 82: return "Heavy Showers"
        case 85: return "Light Snow Showers"
        case 86: return "Snow Showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm"
        default: return "Unknown"
        }
    }

    // MARK: - Moon Phase Calculation
    func calculateMoonPhase(for date: Date) -> MoonPhase {
        // Reference: Known new moon date - Jan 6, 2000 18:14 UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let referenceComponents = DateComponents(
            calendar: calendar,
            timeZone: TimeZone(identifier: "UTC"),
            year: 2000, month: 1, day: 6, hour: 18, minute: 14
        )
        guard let referenceNewMoon = referenceComponents.date else {
            return MoonPhase(phase: 0, name: "Unknown", icon: "moon.fill")
        }

        let synodicMonth = 29.53058867  // Average lunar cycle in days

        let daysSinceReference = date.timeIntervalSince(referenceNewMoon) / 86400
        var cyclePosition = daysSinceReference.truncatingRemainder(dividingBy: synodicMonth)
        if cyclePosition < 0 { cyclePosition += synodicMonth }
        let phase = cyclePosition / synodicMonth  // 0.0 to 1.0

        let (name, icon) = phaseNameAndIcon(for: phase)

        return MoonPhase(phase: phase, name: name, icon: icon)
    }

    private func phaseNameAndIcon(for phase: Double) -> (String, String) {
        switch phase {
        case 0.00..<0.03, 0.97...1.0:
            return ("New Moon", "moonphase.new.moon")
        case 0.03..<0.22:
            return ("Waxing Crescent", "moonphase.waxing.crescent")
        case 0.22..<0.28:
            return ("First Quarter", "moonphase.first.quarter")
        case 0.28..<0.47:
            return ("Waxing Gibbous", "moonphase.waxing.gibbous")
        case 0.47..<0.53:
            return ("Full Moon", "moonphase.full.moon")
        case 0.53..<0.72:
            return ("Waning Gibbous", "moonphase.waning.gibbous")
        case 0.72..<0.78:
            return ("Last Quarter", "moonphase.last.quarter")
        case 0.78..<0.97:
            return ("Waning Crescent", "moonphase.waning.crescent")
        default:
            return ("Moon", "moon.fill")
        }
    }
}

// =============================================================
// MARK: - 3. MAIN HOME SCREEN
// =============================================================

struct KiawahConciergeView: View {
    @StateObject private var viewModel = RentalViewModel()
    @State private var showingWifi = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                if let heroImage = viewModel.heroImage {
                    Image(uiImage: heroImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .overlay(
                            LinearGradient(
                                gradient: Gradient(colors: [.black.opacity(0.4), .clear, .black.opacity(0.4)]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .ignoresSafeArea()
                        .transition(.opacity)
                } else {
                    ZStack {
                        Color.black.ignoresSafeArea()
                        ProgressView()
                    }
                }
                
                VStack {
                    Spacer()
                    
                    VStack(spacing: 5) {
                        Text("Welcome!")
                            .font(.system(size: 60, weight: .ultraLight, design: .rounded))
                        Text(viewModel.guestName)
                            .font(.system(size: 130, weight: .light, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .shadow(color: .black.opacity(0.6), radius: 15, x: 0, y: 10)
                    .padding(40)
                    .background(
                        Circle()
                            .fill(Color.gray.opacity(0.1))
                            .blur(radius: 40)
                    )
                    
                    Spacer()
                    
                    // The Dock
                    HStack(spacing: 40) {
                        NavigationLink(destination: SettleInView(viewModel: viewModel)) {
                            DockButton(icon: "house.fill", label: "Settle In")
                        }
                        .buttonStyle(.card)
                        .tint(.gray)

                        NavigationLink(destination: WeatherDetailView(viewModel: viewModel)) {
                            DockButton(icon: "cloud.sun.fill", label: "Weather")
                        }
                        .buttonStyle(.card)
                        .tint(.gray)

                        NavigationLink(destination: CategoryBrowserView(categories: viewModel.categories, diningSection: viewModel.diningSection)) {
                            DockButton(icon: "mappin.and.ellipse", label: "Explore")
                        }
                        .buttonStyle(.card)
                        .tint(.gray)
                    }
                    .padding(.horizontal, 60)
                    .padding(.vertical, 30)
                    .background(
                        RoundedRectangle(cornerRadius: 40)
                            .fill(.ultraThinMaterial)
                    )
                    .padding(.bottom, 50)
                }
            }
            .overlay(alignment: .topTrailing) {
                WeatherTimeHeader(
                    temp: viewModel.currentTemp,
                    low: viewModel.currentLow,
                    condition: viewModel.currentCondition,
                    icon: viewModel.currentIcon
                )
                .padding(40)
            }
            .sheet(isPresented: $showingWifi) {
                WifiModalView(ssid: viewModel.wifiSSID, pass: viewModel.wifiPass, isPresented: $showingWifi)
            }
            .task {
                await viewModel.fetchAllData()
            }
        }
    }
}

struct DockButton: View {
    let icon: String
    let label: String
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 40))
            Text(label)
                .font(.system(size: 24, weight: .medium, design: .rounded))
        }
        .frame(width: 220, height: 180)
    }
}

struct WeatherTimeHeader: View {
    let temp: Int
    let low: Int
    let condition: String
    let icon: String
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack(spacing: 30) {
            HStack(spacing: 15) {
                Image(systemName: icon)
                    .renderingMode(.original)
                    .font(.system(size: 40))
                
                VStack(alignment: .leading) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(temp)°")
                            .font(.system(size: 45, weight: .semibold, design: .rounded))
                        Text("\(low)°")
                            .font(.system(size: 30, weight: .light, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Text(condition)
                        .font(.system(size: 20, weight: .medium, design: .rounded))
                        .textCase(.uppercase)
                }
            }
            
            Rectangle()
                .fill(.white.opacity(0.3))
                .frame(width: 2, height: 60)
            
            Text(currentTime, style: .time)
                .font(.system(size: 60, weight: .thin, design: .rounded))
                .onReceive(timer) { currentTime = $0 }
        }
        .foregroundColor(.white)
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(.ultraThinMaterial.opacity(0.5))
        )
    }
}

// =============================================================
// MARK: - WEATHER DETAIL VIEW
// =============================================================

struct WeatherDetailView: View {
    @ObservedObject var viewModel: RentalViewModel

    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [Color.blue.opacity(0.3), Color.black, Color.blue.opacity(0.2)]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 40) {
                    // Current Weather Header with Sun & Moon
                    Button(action: {}) {
                        HStack(spacing: 0) {
                            // Sunrise / Sunset - Left
                            HStack(spacing: 30) {
                                VStack(spacing: 8) {
                                    Image(systemName: "sunrise.fill")
                                        .renderingMode(.original)
                                        .font(.system(size: 36))
                                    Text(viewModel.sunTimes.sunrise)
                                        .font(.system(size: 22, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Sunrise")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(.white.opacity(0.5))
                                }

                                VStack(spacing: 8) {
                                    Image(systemName: "sunset.fill")
                                        .renderingMode(.original)
                                        .font(.system(size: 36))
                                    Text(viewModel.sunTimes.sunset)
                                        .font(.system(size: 22, weight: .medium, design: .rounded))
                                        .foregroundColor(.white)
                                    Text("Sunset")
                                        .font(.system(size: 14, weight: .light))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                            .frame(width: 220)

                            Spacer()

                            // Current Weather - Center
                            HStack(spacing: 30) {
                                Image(systemName: viewModel.currentIcon)
                                    .renderingMode(.original)
                                    .font(.system(size: 90))

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Text("\(viewModel.currentTemp)°")
                                            .font(.system(size: 80, weight: .semibold, design: .rounded))
                                        Text("\(viewModel.currentLow)°")
                                            .font(.system(size: 44, weight: .light, design: .rounded))
                                            .foregroundColor(.white.opacity(0.5))
                                    }
                                    Text(viewModel.currentCondition)
                                        .font(.system(size: 28, weight: .medium, design: .rounded))
                                        .textCase(.uppercase)
                                }
                            }

                            Spacer()

                            // Moon Phase - Right
                            VStack(spacing: 8) {
                                Image(systemName: viewModel.moonPhase.icon)
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)

                                Text(viewModel.moonPhase.name)
                                    .font(.system(size: 20, weight: .medium, design: .rounded))
                                    .foregroundColor(.white)

                                Text("\(illuminationPercent(viewModel.moonPhase.phase))%")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.white.opacity(0.5))
                            }
                            .frame(width: 220)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 50)
                        .padding(.vertical, 35)
                        .frame(maxWidth: 1200)
                        .background(RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.card)

                    // 3-Hour Forecast
                    Button(action: {}) {
                        VStack(alignment: .leading, spacing: 25) {
                            Label("Next 24 Hours", systemImage: "clock")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))

                            if viewModel.hourlyForecast.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                HStack(spacing: 20) {
                                    ForEach(viewModel.hourlyForecast) { hour in
                                        VStack(spacing: 10) {
                                            Text(hourLabel(hour.time))
                                                .font(.system(size: 20, weight: .medium, design: .rounded))
                                                .foregroundColor(.white.opacity(0.7))

                                            Image(systemName: hour.icon)
                                                .renderingMode(.original)
                                                .font(.system(size: 32))

                                            Text("\(hour.temp)°")
                                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)

                                            if hour.precipChance > 0 {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "drop.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.cyan)
                                                    Text("\(hour.precipChance)%")
                                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                                        .foregroundColor(.cyan)
                                                }
                                            } else {
                                                Spacer().frame(height: 18)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(35)
                        .frame(maxWidth: 1000)
                        .background(RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.card)

                    // 7-Day Forecast
                    Button(action: {}) {
                        VStack(alignment: .leading, spacing: 25) {
                            Label("7-Day Forecast", systemImage: "calendar")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))

                            if viewModel.forecast.isEmpty {
                                ProgressView()
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            } else {
                                HStack(spacing: 25) {
                                    ForEach(viewModel.forecast) { day in
                                        VStack(spacing: 12) {
                                            Text(dayName(day.date))
                                                .font(.system(size: 22, weight: .medium, design: .rounded))
                                                .foregroundColor(.white.opacity(0.7))

                                            Image(systemName: day.icon)
                                                .renderingMode(.original)
                                                .font(.system(size: 36))

                                            Text("\(day.high)°")
                                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)

                                            Text("\(day.low)°")
                                                .font(.system(size: 22, weight: .light, design: .rounded))
                                                .foregroundColor(.white.opacity(0.5))

                                            if day.precipChance > 0 {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "drop.fill")
                                                        .font(.system(size: 12))
                                                        .foregroundColor(.cyan)
                                                    Text("\(day.precipChance)%")
                                                        .font(.system(size: 14, weight: .medium, design: .rounded))
                                                        .foregroundColor(.cyan)
                                                }
                                            } else {
                                                Spacer().frame(height: 18)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                        .padding(35)
                        .frame(maxWidth: 1100)
                        .background(RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.card)

                    // Tides - Centered, Horizontal Layout
                    Button(action: {}) {
                        VStack(spacing: 20) {
                            Label("Today's Tides", systemImage: "water.waves")
                                .font(.system(size: 28, weight: .semibold, design: .rounded))
                                .foregroundColor(.white.opacity(0.7))

                            if viewModel.tideEvents.isEmpty {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Loading tide data…")
                                        .font(.system(size: 18, weight: .light, design: .rounded))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                                .padding()
                            } else {
                                HStack(spacing: 0) {
                                    ForEach(Array(viewModel.tideEvents.enumerated()), id: \.element.id) { index, tide in
                                        VStack(spacing: 12) {
                                            Image(systemName: tide.type == "High" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                                .foregroundColor(tide.type == "High" ? .cyan : .blue)
                                                .font(.system(size: 36))

                                            Text(tide.type)
                                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                                .foregroundColor(.white)

                                            Text(tide.time)
                                                .font(.system(size: 24, weight: .medium, design: .rounded))
                                                .foregroundColor(.white)

                                            Text(tide.height)
                                                .font(.system(size: 16, weight: .light, design: .rounded))
                                                .foregroundColor(.white.opacity(0.6))
                                        }
                                        .frame(maxWidth: .infinity)

                                        if index < viewModel.tideEvents.count - 1 {
                                            Divider()
                                                .frame(height: 80)
                                                .background(Color.white.opacity(0.2))
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.vertical, 30)
                        .frame(maxWidth: 1000)
                        .background(RoundedRectangle(cornerRadius: 30).fill(.ultraThinMaterial))
                    }
                    .buttonStyle(.card)

                    Spacer(minLength: 60)
                }
                .padding(60)
            }
        }
        .navigationTitle("Weather")
    }

    private func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func hourLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        if cal.isDate(date, equalTo: now, toGranularity: .hour) {
            return "Now"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }

    private func illuminationPercent(_ phase: Double) -> Int {
        // Phase 0 or 1 = new moon (0% illuminated)
        // Phase 0.5 = full moon (100% illuminated)
        // Use cosine function to calculate illumination
        let illumination = (1 - cos(phase * 2 * .pi)) / 2
        return Int((illumination * 100).rounded())
    }
}

// =============================================================
// MARK: - SETTLE IN VIEW
// =============================================================

struct SettleInView: View {
    @ObservedObject var viewModel: RentalViewModel

    var body: some View {
        SettleInCardGallery(viewModel: viewModel)
            .background(Color(white: 0.9).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settle In")
                        .font(.system(size: 70, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                }
            }
    }
}

// --- Settle In Card Gallery ---
struct SettleInCardGallery: View {
    @ObservedObject var viewModel: RentalViewModel

    private let columns = [
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40),
        GridItem(.flexible(), spacing: 40)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                NavigationLink(destination: WifiDetailView(ssid: viewModel.wifiSSID, pass: viewModel.wifiPass)) {
                    SettleInCardTile(icon: "wifi", title: "WiFi", color: .blue)
                }
                .buttonStyle(.card)

                ForEach(viewModel.settleInCards.filter { !$0.content.isEmpty }) { card in
                    NavigationLink(destination: SettleInDetailView(card: card)) {
                        SettleInCardTile(icon: card.icon, title: card.title,
                                         color: cardColor(for: card.title))
                    }
                    .buttonStyle(.card)
                }

                NavigationLink(destination: HowDoIBrowserView()) {
                    SettleInCardTile(icon: "questionmark.circle.fill", title: "How Do I…", color: .orange)
                }
                .buttonStyle(.card)
            }
            .padding(60)
        }
    }

    private func cardColor(for title: String) -> Color {
        switch title {
        case "Check Out Instructions": return .purple
        case "Emergency Info": return .red
        case "Parking & Gate Code": return .green
        case "Trash & Recycling": return .mint
        case "Pool & Hot Tub": return .cyan
        default: return .gray
        }
    }
}

struct SettleInCardTile: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.2))
                    .frame(width: 100, height: 100)
                Image(systemName: icon)
                    .font(.system(size: 45))
                    .foregroundColor(color)
            }

            Text(title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 280, height: 220)
        .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
    }
}

// --- Settle In Detail ---
struct SettleInDetailView: View {
    let card: SettleInCard
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Image(systemName: card.icon)
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                
                Text(card.title)
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                Text(card.content)
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .lineSpacing(12)
                    .frame(maxWidth: 900)
                    .padding(40)
                    .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
                
                Spacer()
            }
            .padding(.top, 80)
        }
    }
}

// --- WiFi Detail ---
struct WifiDetailView: View {
    let ssid: String
    let pass: String
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 40) {
                Image(systemName: "wifi")
                    .font(.system(size: 70))
                    .foregroundColor(.blue)
                
                Text("Property WiFi")
                    .font(.system(size: 60, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                HStack(spacing: 80) {
                    VStack(alignment: .leading, spacing: 25) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("NETWORK")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                            Text(ssid)
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("PASSWORD")
                                .font(.system(size: 18, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.5))
                            Text(pass)
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                                .foregroundColor(.white)
                        }
                    }
                    
                    VStack(spacing: 12) {
                        AsyncImage(url: URL(string: "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=WIFI:S:\(ssid);T:WPA;P:\(pass);;")) { phase in
                            if let image = phase.image {
                                image.resizable()
                                    .interpolation(.none)
                                    .frame(width: 300, height: 300)
                                    .cornerRadius(20)
                            } else {
                                ProgressView().frame(width: 300, height: 300)
                            }
                        }
                        Text("Scan to connect")
                            .font(.system(size: 16, weight: .light, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(40)
                .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
                
                Spacer()
            }
            .padding(.top, 80)
        }
    }
}

// =============================================================
// MARK: - HOW DO I... BROWSER
// =============================================================

struct HowDoIBrowserView: View {
    let cards: [HowDoICard] = [
        HowDoICard(title: "Thermostat", icon: "thermometer.medium",
                    instructions: "The Ecobee thermostat is in the main hallway.\n\n• Tap the screen to wake it up\n• Swipe up/down to adjust temperature\n• The system is set to auto — it will heat or cool as needed\n• Please keep between 68°–76° to avoid excessive energy use\n• If the screen is blank, check the breaker labeled 'HVAC' in the garage panel"),
        HowDoICard(title: "Ceiling Fans", icon: "fan.fill",
                    instructions: "Each ceiling fan has a small remote control mounted on the wall nearby.\n\n• Top button: Fan on/off\n• Middle buttons: Speed (low / medium / high)\n• Bottom button: Light on/off\n• If a remote doesn't work, try replacing the battery (CR2032) — spares are in the kitchen junk drawer"),
        HowDoICard(title: "Smart Door Lock", icon: "lock.fill",
                    instructions: "The front door uses a Schlage smart lock.\n\n• Your entry code is the last 4 digits of your phone number + 00\n• Press the Schlage button, then enter your code\n• To lock: just press the Schlage button once\n• If the lock beeps 3 times, batteries are low — replacements are under the kitchen sink\n• The deadbolt can always be turned manually from inside"),
        HowDoICard(title: "TV & Apple TV", icon: "appletv.fill",
                    instructions: "Each TV is controlled by the Apple TV remote (the small silver one).\n\n• Press any button to wake the TV\n• Use the touch surface on the remote to navigate\n• Press Menu to go back\n• For streaming apps: select from the home screen or use the dock buttons in this app\n• Volume is controlled by the TV remote (the larger black remote)"),
        HowDoICard(title: "Washer & Dryer", icon: "washer.fill",
                    instructions: "The washer and dryer are in the laundry room off the kitchen.\n\n• Washer: Turn the dial to 'Normal', press Start\n• Dryer: Turn the dial to 'Auto Dry', press Start\n• Detergent pods are on the shelf above the washer\n• Please clean the dryer lint trap after each use\n• If the washer won't start, make sure the door is fully closed until it clicks"),
        HowDoICard(title: "Grill", icon: "flame.fill",
                    instructions: "The gas grill is on the back deck.\n\n• Open the propane tank valve (turn counter-clockwise)\n• Open the grill lid before lighting\n• Turn burner knobs to 'High' and press the igniter button\n• Allow 10 minutes to preheat\n• When done: turn all burners off, then close the propane valve\n• Please brush the grates after use — brush is hanging on the side")
    ]
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("How Do I…")
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .padding(.bottom, 10)
                
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 25),
                    GridItem(.flexible(), spacing: 25),
                    GridItem(.flexible(), spacing: 25)
                ], spacing: 25) {
                    ForEach(cards) { card in
                        NavigationLink(destination: HowDoIDetailView(card: card)) {
                            HowDoITile(card: card)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(60)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.orange.opacity(0.1), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
    }
}

struct HowDoITile: View {
    let card: HowDoICard
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: card.icon)
                .font(.system(size: 50))
                .foregroundColor(.orange)
            Text(card.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(width: 320, height: 200)
        .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
    }
}

struct HowDoIDetailView: View {
    let card: HowDoICard
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 40) {
                    Image(systemName: card.icon)
                        .font(.system(size: 80))
                        .foregroundColor(.orange)
                    
                    Text(card.title)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(card.instructions)
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(10)
                        .frame(maxWidth: 1000)
                        .padding(40)
                        .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
                    
                    Spacer(minLength: 80)
                }
                .padding(.top, 60)
            }
        }
    }
}

// =============================================================
// MARK: - EXPLORE: CATEGORY BROWSER (Levels 1-3)
// =============================================================

struct CategoryBrowserView: View {
    let categories: [PlaceCategory]
    let diningSection: DiningSection?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 50) {
                ForEach(categories) { category in
                    // Route Dining to rich view if dining data exists
                    if category.name.lowercased() == "dining", let dining = diningSection {
                        NavigationLink(destination: DiningCollectionView(diningSection: dining)) {
                            CategoryTile(category: category)
                        }
                        .buttonStyle(.card)
                    } else {
                        NavigationLink(destination: PlaceCardsView(category: category)) {
                            CategoryTile(category: category)
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(.horizontal, 80)
            .padding(.vertical, 60)
        }
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.black, Color.blue.opacity(0.15), Color.black]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Explore Kiawah")
    }
}

struct CategoryTile: View {
    let category: PlaceCategory
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: URL(string: category.coverImageURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 400, height: 500)
            .clipped()
            
            LinearGradient(
                gradient: Gradient(colors: [.clear, .clear, .black.opacity(0.8)]),
                startPoint: .top,
                endPoint: .bottom
            )
            
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: category.icon)
                    .font(.system(size: 36))
                    .foregroundColor(.white.opacity(0.9))
                Text(category.name)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("\(category.places.count) \(category.places.count == 1 ? "place" : "places")")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(30)
        }
        .frame(width: 400, height: 500)
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 15)
    }
}

struct PlaceCardsView: View {
    let category: PlaceCategory
    @FocusState private var focusedPlaceID: UUID?
    
    private var focusedPlace: LocalRecommendation? {
        category.places.first(where: { $0.id == focusedPlaceID })
    }
    
    var body: some View {
        ZStack {
            if let focused = focusedPlace {
                AsyncImage(url: URL(string: focused.imageURL)) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color.black }
                .blur(radius: 80)
                .opacity(0.3)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: focusedPlaceID)
            } else {
                Color.black.ignoresSafeArea()
            }
            
            VStack(alignment: .leading, spacing: 40) {
                HStack(spacing: 20) {
                    Image(systemName: category.icon)
                        .font(.system(size: 44))
                    Text(category.name)
                        .font(.system(size: 60, weight: .bold, design: .rounded))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 80)
                .padding(.top, 40)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 40) {
                        ForEach(category.places) { place in
                            NavigationLink(destination: PlaceDetailView(place: place)) {
                                PlaceCard(place: place)
                            }
                            .buttonStyle(.card)
                            .focused($focusedPlaceID, equals: place.id)
                        }
                    }
                    .padding(.horizontal, 80)
                    .padding(.vertical, 40)
                }
                
                Spacer()
            }
        }
    }
}

struct PlaceCard: View {
    let place: LocalRecommendation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AsyncImage(url: URL(string: place.imageURL)) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Color.gray.opacity(0.2)
                        ProgressView()
                    }
                }
            }
            .frame(width: 380, height: 250)
            .clipped()
            
            VStack(alignment: .leading, spacing: 8) {
                Text(place.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(place.description)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(.blue)
                    Text(place.address)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(width: 380, height: 400)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
    }
}

struct PlaceDetailView: View {
    let place: LocalRecommendation
    
    var body: some View {
        ZStack {
            AsyncImage(url: URL(string: place.imageURL)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.clear }
            .blur(radius: 60)
            .opacity(0.25)
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 50) {
                    AsyncImage(url: URL(string: place.imageURL)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            ZStack {
                                Color.gray.opacity(0.1)
                                ProgressView()
                            }
                        }
                    }
                    .frame(width: 1100, height: 550)
                    .clipShape(RoundedRectangle(cornerRadius: 30))
                    .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 25)
                    
                    VStack(spacing: 25) {
                        Text(place.name)
                            .font(.system(size: 80, weight: .heavy, design: .rounded))
                            .tracking(-2)
                            .foregroundColor(.primary)
                        
                        if let type = place.type {
                            Text(type.uppercased())
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .tracking(3)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                        }
                        
                        Text(place.description)
                            .font(.system(size: 32, weight: .light))
                            .multilineTextAlignment(.center)
                            .lineSpacing(10)
                            .frame(maxWidth: 1000)
                            .foregroundColor(.primary.opacity(0.9))
                            .padding(.top, 10)
                        
                        HStack(spacing: 20) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Address")
                                    .font(.system(size: 18, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(place.address)
                                    .font(.system(size: 28, weight: .medium, design: .rounded))
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(30)
                        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                        .padding(.top, 20)
                    }
                    
                    Spacer(minLength: 80)
                }
                .padding(.top, 60)
            }
        }
        .background(.regularMaterial)
    }
}

// =============================================================
// MARK: - DINING COLLECTION (Rich Dining Experience)
// =============================================================

struct DiningCollectionView: View {
    let diningSection: DiningSection

    // Group venues by location
    private var venuesByLocation: [(location: String, venues: [DiningVenue])] {
        let grouped = Dictionary(grouping: diningSection.venues, by: { $0.location })
        let locationOrder = ["The Sanctuary", "The Ocean Course Clubhouse", "Turtle Point Clubhouse",
                            "Cougar Point Clubhouse", "Osprey Point Clubhouse", "Night Heron Park",
                            "The Treehouse Activity Center"]

        var result: [(location: String, venues: [DiningVenue])] = []

        // Add locations in preferred order
        for loc in locationOrder {
            if let venues = grouped[loc], !venues.isEmpty {
                result.append((location: loc, venues: venues))
            }
        }

        // Add any remaining locations not in the order
        for (loc, venues) in grouped where !locationOrder.contains(loc) && !loc.isEmpty {
            result.append((location: loc, venues: venues))
        }

        // Add venues with empty location at the end
        if let emptyLoc = grouped[""], !emptyLoc.isEmpty {
            result.append((location: "Around the Island", venues: emptyLoc))
        }

        return result
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                // Hero Section
                ZStack(alignment: .bottomLeading) {
                    AsyncImage(url: URL(string: diningSection.heroImage)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray.opacity(0.3)
                        }
                    }
                    .frame(height: 400)
                    .clipped()

                    LinearGradient(
                        gradient: Gradient(colors: [.clear, .black.opacity(0.8)]),
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 12) {
                        Text(diningSection.title)
                            .font(.system(size: 60, weight: .bold, design: .rounded))
                            .foregroundColor(.white)

                        Text(diningSection.intro)
                            .font(.system(size: 24, weight: .light))
                            .foregroundColor(.white.opacity(0.9))
                            .lineLimit(2)
                    }
                    .padding(40)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding(30)
                }
                .frame(maxWidth: .infinity)

                // Venue Groups by Location
                ForEach(venuesByLocation, id: \.location) { group in
                    VStack(alignment: .leading, spacing: 25) {
                        // Location Header
                        HStack(spacing: 15) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.blue)
                            Text(group.location)
                                .font(.system(size: 36, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 60)

                        // Horizontal scroll of venue cards
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 35) {
                                ForEach(group.venues) { venue in
                                    NavigationLink(destination: DiningVenueDetailView(venue: venue)) {
                                        DiningVenueCard(venue: venue)
                                    }
                                    .buttonStyle(.card)
                                }
                            }
                            .padding(.horizontal, 60)
                        }
                    }
                    .padding(.bottom, 20)
                }

                Spacer(minLength: 60)
            }
        }
        .background(Color(white: 0.9).ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

struct DiningVenueCard: View {
    let venue: DiningVenue

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hero Image with Logo overlay
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: URL(string: venue.heroImage)) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        ZStack {
                            Color.gray.opacity(0.2)
                            ProgressView()
                        }
                    }
                }
                .frame(width: 420, height: 240)
                .clipped()

                // Logo in corner
                if !venue.logoImage.isEmpty {
                    AsyncImage(url: URL(string: venue.logoImage)) { phase in
                        if let image = phase.image {
                            image.resizable().aspectRatio(contentMode: .fit)
                        }
                    }
                    .frame(width: 70, height: 70)
                    .background(Circle().fill(.white))
                    .clipShape(Circle())
                    .padding(15)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Text(venue.name)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)

                if !venue.shortDescription.isEmpty {
                    Text(venue.shortDescription)
                        .font(.system(size: 18, weight: .light))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                // Cuisine tags
                if !venue.cuisines.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(venue.cuisines.prefix(3), id: \.self) { cuisine in
                            Text(cuisine)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.blue)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(Color.blue.opacity(0.15)))
                        }
                    }
                    .padding(.top, 6)
                }
            }
            .padding(20)
        }
        .frame(width: 420, height: 450)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
    }
}

struct DiningVenueDetailView: View {
    let venue: DiningVenue

    var body: some View {
        ZStack {
            // Light background with subtle image blur
            Color(white: 0.9).ignoresSafeArea()

            AsyncImage(url: URL(string: venue.heroImage)) { img in
                img.resizable().aspectRatio(contentMode: .fill)
            } placeholder: { Color.clear }
            .blur(radius: 80)
            .opacity(0.15)
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 50) {
                    // Hero Image - focusable for tvOS scrolling
                    Button(action: {}) {
                        ZStack(alignment: .bottomLeading) {
                            AsyncImage(url: URL(string: venue.heroImage)) { phase in
                                if let image = phase.image {
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } else {
                                    ZStack {
                                        Color.gray.opacity(0.1)
                                        ProgressView()
                                    }
                                }
                            }
                            .frame(width: 1200, height: 500)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 30))

                            // Logo overlay
                            if !venue.logoImage.isEmpty {
                                AsyncImage(url: URL(string: venue.logoImage)) { phase in
                                    if let image = phase.image {
                                        image.resizable().aspectRatio(contentMode: .fit)
                                    }
                                }
                                .frame(width: 120, height: 120)
                                .background(Circle().fill(.white))
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.3), radius: 10)
                                .padding(30)
                            }
                        }
                        .shadow(color: .black.opacity(0.4), radius: 40, x: 0, y: 25)
                    }
                    .buttonStyle(.card)

                    // Name and Status - focusable section
                    Button(action: {}) {
                        VStack(spacing: 20) {
                            Text(venue.name)
                                .font(.system(size: 70, weight: .heavy, design: .rounded))
                                .tracking(-2)
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)

                            if !venue.location.isEmpty {
                                HStack(spacing: 10) {
                                    Image(systemName: "mappin.circle.fill")
                                        .foregroundColor(.blue)
                                    Text(venue.location)
                                        .font(.system(size: 24, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Hours
                            if !venue.hours.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "clock.fill")
                                        .foregroundColor(.orange)
                                    Text(venue.hours)
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                                .padding(.horizontal, 30)
                                .padding(.vertical, 15)
                                .background(RoundedRectangle(cornerRadius: 15).fill(.ultraThinMaterial))
                            }

                            // Cuisine tags
                            if !venue.cuisines.isEmpty {
                                HStack(spacing: 12) {
                                    ForEach(venue.cuisines, id: \.self) { cuisine in
                                        Text(cuisine)
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundColor(.blue)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 8)
                                            .background(Capsule().fill(Color.blue.opacity(0.15)))
                                    }
                                }
                            }
                        }
                        .padding(30)
                    }
                    .buttonStyle(.card)

                    // Description - focusable section
                    if !venue.shortDescription.isEmpty {
                        Button(action: {}) {
                            Text(venue.shortDescription)
                                .font(.system(size: 32, weight: .light))
                                .multilineTextAlignment(.center)
                                .lineSpacing(10)
                                .frame(maxWidth: 1000)
                                .foregroundColor(.primary.opacity(0.9))
                                .padding(30)
                        }
                        .buttonStyle(.card)
                    }

                    // Reservations Card - focusable section
                    if venue.reservationRequired == true || !venue.reservationPhone.isEmpty {
                        Button(action: {}) {
                            VStack(spacing: 20) {
                                Label("Reservations", systemImage: "calendar.badge.clock")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)

                                if venue.reservationRequired == true {
                                    Text("Reservations Recommended")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundColor(.orange)
                                }

                                if !venue.reservationPhone.isEmpty {
                                    HStack(spacing: 12) {
                                        Image(systemName: "phone.fill")
                                            .foregroundColor(.green)
                                        Text(venue.reservationPhone)
                                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                    }
                                }
                            }
                            .padding(35)
                            .frame(maxWidth: 600)
                            .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.card)
                    }

                    // Google Reviews Section
                    if let rating = venue.googleRating, let reviewCount = venue.googleReviewCount {
                        VStack(alignment: .leading, spacing: 25) {
                            // Header with overall rating
                            HStack(spacing: 20) {
                                Label("Reviews", systemImage: "star.bubble.fill")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)

                                Spacer()

                                HStack(spacing: 8) {
                                    HStack(spacing: 4) {
                                        ForEach(0..<5) { index in
                                            Image(systemName: starIcon(for: index, rating: rating))
                                                .foregroundColor(.yellow)
                                                .font(.system(size: 22))
                                        }
                                    }
                                    Text(String(format: "%.1f", rating))
                                        .font(.system(size: 24, weight: .bold, design: .rounded))
                                        .foregroundColor(.primary)
                                    Text("(\(reviewCount))")
                                        .font(.system(size: 20, weight: .light))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 35)

                            // Individual reviews
                            if let reviews = venue.googleReviews, !reviews.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 20) {
                                        ForEach(reviews) { review in
                                            Button(action: {}) {
                                                VStack(alignment: .leading, spacing: 15) {
                                                    // Author and rating
                                                    HStack(spacing: 12) {
                                                        if let photoUrl = review.authorPhoto, !photoUrl.isEmpty {
                                                            AsyncImage(url: URL(string: photoUrl)) { phase in
                                                                if let image = phase.image {
                                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                                } else {
                                                                    Circle().fill(Color.gray.opacity(0.3))
                                                                }
                                                            }
                                                            .frame(width: 50, height: 50)
                                                            .clipShape(Circle())
                                                        } else {
                                                            Image(systemName: "person.circle.fill")
                                                                .font(.system(size: 40))
                                                                .foregroundColor(.gray)
                                                        }

                                                        VStack(alignment: .leading, spacing: 4) {
                                                            Text(review.authorName)
                                                                .font(.system(size: 20, weight: .semibold))
                                                                .foregroundColor(.primary)
                                                                .lineLimit(1)
                                                            HStack(spacing: 3) {
                                                                ForEach(0..<5) { index in
                                                                    Image(systemName: index < review.rating ? "star.fill" : "star")
                                                                        .foregroundColor(.yellow)
                                                                        .font(.system(size: 14))
                                                                }
                                                                Text(review.relativeTime)
                                                                    .font(.system(size: 14, weight: .light))
                                                                    .foregroundColor(.secondary)
                                                                    .padding(.leading, 5)
                                                            }
                                                        }
                                                    }

                                                    // Review text
                                                    Text(review.text)
                                                        .font(.system(size: 18, weight: .light))
                                                        .foregroundColor(.primary.opacity(0.85))
                                                        .lineLimit(5)
                                                        .multilineTextAlignment(.leading)
                                                        .lineSpacing(4)
                                                }
                                                .padding(25)
                                                .frame(width: 400, alignment: .topLeading)
                                                .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
                                            }
                                            .buttonStyle(.card)
                                        }
                                    }
                                    .padding(.horizontal, 35)
                                }
                            }
                        }
                        .frame(maxWidth: 1200)
                    }

                    Spacer(minLength: 80)
                }
                .padding(.top, 40)
            }
        }
        .preferredColorScheme(.light)
    }

    private func starIcon(for index: Int, rating: Double) -> String {
        let threshold = Double(index) + 1
        if rating >= threshold {
            return "star.fill"
        } else if rating >= threshold - 0.5 {
            return "star.leadinghalf.filled"
        } else {
            return "star"
        }
    }
}

// =============================================================
// MARK: - HELPER VIEWS
// =============================================================

struct WifiModalView: View {
    let ssid: String
    let pass: String
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 40) {
            Text("Property WiFi").font(.system(size: 60, weight: .bold))
            
            HStack(spacing: 80) {
                VStack(alignment: .leading, spacing: 30) {
                    Label(ssid, systemImage: "network").font(.title)
                    Label(pass, systemImage: "lock.fill").font(.title)
                }
                
                AsyncImage(url: URL(string: "https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=WIFI:S:\(ssid);T:WPA;P:\(pass);;")) { phase in
                    if let image = phase.image {
                        image.resizable()
                            .interpolation(.none)
                            .frame(width: 350, height: 350)
                            .cornerRadius(20)
                    } else {
                        ProgressView().frame(width: 350, height: 350)
                    }
                }
            }
            
            Button("Dismiss") { isPresented = false }
                .buttonStyle(.bordered)
                .tint(.blue)
                .padding(.top, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
