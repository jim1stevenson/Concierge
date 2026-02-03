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

struct DiningVenue: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let location: String
    let type: String
    let cuisines: [String]
    let price: String
    let mealTimes: [String]
    let shortDescription: String
    let heroImage: String
    let logoImage: String
    let statusLine: String
    let hours: String
    let reservationRequired: Bool?
    let reservationPhone: String
    let reservationUrl: String
    let description: String
    let attire: String
    let signatureTitle: String
    let signatureText: String
    let chefName: String
    let chefBio: String
    let gallery: [String]
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
    @Published var currentTemp: Int = 0
    @Published var currentLow: Int = 0
    @Published var currentCondition: String = ""
    @Published var currentIcon: String = "cloud.fill"
    @Published var sunTimes: SunTimes = SunTimes(sunrise: "--", sunset: "--")
    @Published var tideEvents: [TideEvent] = []
    
    @Published var settleInCards: [SettleInCard] = []
    
    private let lat = 32.6082
    private let lon = -80.0848
    private let weatherAPIKey = Secrets.weatherAPIKey
    private let noaaStation = "8667062"
    
    // MARK: - Fetch All Data
    func fetchAllData() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.fetchRentalData() }
            group.addTask { await self.fetchWeather() }
            group.addTask { await self.fetchSunTimes() }
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
                SettleInCard(title: "Check Out Instructions", icon: "door.open.right",
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
            
            await MainActor.run {
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
    
    // MARK: - Weather
    func fetchWeather() async {
        let urlString = "https://api.openweathermap.org/data/2.5/forecast?lat=\(lat)&lon=\(lon)&appid=\(weatherAPIKey)&units=imperial&cnt=40"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["list"] as? [[String: Any]] else { return }
            
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            
            var dailyData: [String: (highs: [Double], lows: [Double], icon: String, condition: String)] = [:]
            
            for item in list {
                guard let dtTxt = item["dt_txt"] as? String,
                      let main = item["main"] as? [String: Any],
                      let tempMax = main["temp_max"] as? Double,
                      let tempMin = main["temp_min"] as? Double,
                      let weatherArr = item["weather"] as? [[String: Any]],
                      let weather = weatherArr.first,
                      let owIcon = weather["icon"] as? String,
                      let desc = weather["main"] as? String else { continue }
                
                let dayKey = String(dtTxt.prefix(10))
                var entry = dailyData[dayKey] ?? (highs: [], lows: [], icon: owIcon, condition: desc)
                entry.highs.append(tempMax)
                entry.lows.append(tempMin)
                if dtTxt.contains("12:00:00") {
                    entry.icon = owIcon
                    entry.condition = desc
                }
                dailyData[dayKey] = entry
            }
            
            let sortedDays = dailyData.keys.sorted().prefix(5)
            var forecastDays: [ForecastDay] = []
            
            for dayKey in sortedDays {
                guard let entry = dailyData[dayKey],
                      let date = dayFormatter.date(from: dayKey) else { continue }
                forecastDays.append(ForecastDay(
                    date: date,
                    high: Int(entry.highs.max() ?? 0),
                    low: Int(entry.lows.min() ?? 0),
                    icon: Self.sfSymbol(for: entry.icon),
                    condition: entry.condition
                ))
            }
            
            await MainActor.run {
                self.forecast = forecastDays
                self.currentTemp = forecastDays.first?.high ?? 0
                self.currentLow = forecastDays.first?.low ?? 0
                self.currentCondition = forecastDays.first?.condition ?? "—"
                self.currentIcon = forecastDays.first?.icon ?? "cloud.fill"
            }
        } catch {
            print("❌ Weather Error: \(error)")
        }
    }
    
    // MARK: - Sunrise / Sunset
    // FIX: Use formatted=0 to get ISO times, then format ourselves WITHOUT seconds
    func fetchSunTimes() async {
        let urlString = "https://api.sunrise-sunset.org/json?lat=\(lat)&lng=\(lon)&formatted=0&tzid=America/New_York"
        guard let url = URL(string: urlString) else { return }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = json["results"] as? [String: Any],
                  let sunriseStr = results["sunrise"] as? String,
                  let sunsetStr = results["sunset"] as? String else { return }
            
            // Parse ISO 8601 dates and format to h:mm a (no seconds)
            // Try with fractional seconds first, then without
            let isoFrac = ISO8601DateFormatter()
            isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let isoPlain = ISO8601DateFormatter()
            isoPlain.formatOptions = [.withInternetDateTime]
            
            let displayFormatter = DateFormatter()
            displayFormatter.dateFormat = "h:mm a"
            displayFormatter.timeZone = TimeZone(identifier: "America/New_York")
            
            var sunrise = sunriseStr
            var sunset = sunsetStr
            
            if let d = isoFrac.date(from: sunriseStr) ?? isoPlain.date(from: sunriseStr) {
                sunrise = displayFormatter.string(from: d)
            }
            if let d = isoFrac.date(from: sunsetStr) ?? isoPlain.date(from: sunsetStr) {
                sunset = displayFormatter.string(from: d)
            }
            
            await MainActor.run {
                self.sunTimes = SunTimes(sunrise: sunrise, sunset: sunset)
            }
        } catch {
            print("❌ Sunrise Error: \(error)")
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
            
            await MainActor.run {
                self.tideEvents = events
            }
        } catch {
            print("❌ Tide Error: \(error)")
        }
    }
    
    // MARK: - OpenWeather icon to SF Symbol
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
                            .font(.system(size: 130, weight: .bold, design: .rounded))
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
// MARK: - SETTLE IN VIEW
// =============================================================

struct SettleInView: View {
    @ObservedObject var viewModel: RentalViewModel

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            TodaySidebar(viewModel: viewModel)
                .frame(width: 420)

            SettleInCardGallery(viewModel: viewModel)
        }
        .background(Color(white: 0.9).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Settle In")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
            }
        }
    }
}

// --- Today Sidebar ---
struct TodaySidebar: View {
    @ObservedObject var viewModel: RentalViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                // 5-Day Forecast — wrapped in Button for tvOS focus/scroll
                Button(action: {}) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("5-Day Forecast", systemImage: "cloud.sun.fill")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        if viewModel.forecast.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding()
                        } else {
                            ForEach(viewModel.forecast) { day in
                                HStack(spacing: 8) {
                                    Text(dayName(day.date))
                                        .font(.system(size: 22, weight: .medium, design: .rounded))
                                        .frame(width: 70, alignment: .leading)

                                    Image(systemName: day.icon)
                                        .renderingMode(.original)
                                        .font(.system(size: 24))
                                        .frame(width: 35)

                                    Spacer()

                                    Text("\(day.high)°")
                                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                                        .frame(width: 45, alignment: .trailing)

                                    Text("\(day.low)°")
                                        .font(.system(size: 22, weight: .light, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .frame(width: 45, alignment: .trailing)
                                }
                                .foregroundColor(.primary)

                                if day.id != viewModel.forecast.last?.id {
                                    Divider().background(Color.black.opacity(0.15))
                                }
                            }
                        }
                    }
                    .padding(25)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
                }
                .buttonStyle(.card)

                // Sunrise / Sunset — wrapped in Button for tvOS focus/scroll
                Button(action: {}) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Sun", systemImage: "sunrise.fill")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        HStack(spacing: 30) {
                            VStack(spacing: 6) {
                                Image(systemName: "sunrise.fill")
                                    .renderingMode(.original)
                                    .font(.system(size: 30))
                                Text(viewModel.sunTimes.sunrise)
                                    .font(.system(size: 20, weight: .medium, design: .rounded))
                                Text("Sunrise")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            VStack(spacing: 6) {
                                Image(systemName: "sunset.fill")
                                    .renderingMode(.original)
                                    .font(.system(size: 30))
                                Text(viewModel.sunTimes.sunset)
                                    .font(.system(size: 20, weight: .medium, design: .rounded))
                                Text("Sunset")
                                    .font(.system(size: 14, weight: .light))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                    }
                    .padding(25)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
                }
                .buttonStyle(.card)

                // Tides — wrapped in Button for tvOS focus/scroll
                Button(action: {}) {
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Tides", systemImage: "water.waves")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)

                        if viewModel.tideEvents.isEmpty {
                            VStack(spacing: 8) {
                                ProgressView()
                                Text("Loading tide data…")
                                    .font(.system(size: 16, weight: .light, design: .rounded))
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                        } else {
                            ForEach(viewModel.tideEvents) { tide in
                                HStack(spacing: 8) {
                                    Image(systemName: tide.type == "High" ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                        .foregroundColor(tide.type == "High" ? .cyan : .blue)
                                        .font(.system(size: 22))

                                    Text(tide.type)
                                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                                        .frame(width: 50, alignment: .leading)

                                    Spacer()

                                    Text(tide.height)
                                        .font(.system(size: 16, weight: .light, design: .rounded))
                                        .foregroundColor(.secondary)
                                        .frame(minWidth: 55, alignment: .trailing)
                                        .lineLimit(1)

                                    Text(tide.time)
                                        .font(.system(size: 16, weight: .medium, design: .rounded))
                                        .frame(minWidth: 80, alignment: .trailing)
                                        .lineLimit(1)
                                }
                                .foregroundColor(.primary)

                                if tide.id != viewModel.tideEvents.last?.id {
                                    Divider().background(Color.black.opacity(0.15))
                                }
                            }
                        }
                    }
                    .padding(25)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 20).fill(.regularMaterial))
                }
                .buttonStyle(.card)
            }
            .padding(40)
        }
    }

    private func dayName(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }
}

// --- Settle In Card Gallery (Right side) ---
struct SettleInCardGallery: View {
    @ObservedObject var viewModel: RentalViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                NavigationLink(destination: WifiDetailView(ssid: viewModel.wifiSSID, pass: viewModel.wifiPass)) {
                    SettleInCardTile(icon: "wifi", title: "WiFi",
                                     subtitle: "Network: \(viewModel.wifiSSID)", color: .blue)
                }
                .buttonStyle(.card)
                
                ForEach(viewModel.settleInCards.filter { !$0.content.isEmpty }) { card in
                    NavigationLink(destination: SettleInDetailView(card: card)) {
                        SettleInCardTile(icon: card.icon, title: card.title,
                                         subtitle: String(card.content.prefix(60)) + "…",
                                         color: cardColor(for: card.title))
                    }
                    .buttonStyle(.card)
                }
                
                NavigationLink(destination: HowDoIBrowserView()) {
                    SettleInCardTile(icon: "questionmark.circle.fill", title: "How Do I…",
                                     subtitle: "Thermostat, Fans, Smart Lock, TV & more", color: .orange)
                }
                .buttonStyle(.card)
            }
            .padding(40)
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
    let subtitle: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 25) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(color.opacity(0.2))
                    .frame(width: 70, height: 70)
                Image(systemName: icon)
                    .font(.system(size: 30))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)
                Text(subtitle)
                    .font(.system(size: 20, weight: .light))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundColor(.secondary)
        }
        .padding(25)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20).fill(.ultraThinMaterial))
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

                // Status line (e.g., "Offering Dine-In Service")
                if !venue.statusLine.isEmpty {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(venue.statusLine.lowercased().contains("closed") ? Color.red : Color.green)
                            .frame(width: 10, height: 10)
                        Text(venue.statusLine)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.top, 4)
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

                            // Status and Hours
                            if !venue.statusLine.isEmpty || !venue.hours.isEmpty {
                                HStack(spacing: 30) {
                                    if !venue.statusLine.isEmpty {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(venue.statusLine.lowercased().contains("closed") ? Color.red : Color.green)
                                                .frame(width: 12, height: 12)
                                            Text(venue.statusLine)
                                                .font(.system(size: 22, weight: .medium))
                                                .foregroundColor(.primary)
                                        }
                                    }

                                    if !venue.hours.isEmpty {
                                        HStack(spacing: 8) {
                                            Image(systemName: "clock.fill")
                                                .foregroundColor(.orange)
                                            Text(venue.hours)
                                                .font(.system(size: 20, weight: .light))
                                                .foregroundColor(.secondary)
                                        }
                                    }
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

                    // Chef Section - focusable section
                    if !venue.chefName.isEmpty {
                        Button(action: {}) {
                            VStack(spacing: 20) {
                                Label("Meet the Chef", systemImage: "person.crop.circle.fill")
                                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)

                                Text(venue.chefName)
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)

                                if !venue.chefBio.isEmpty {
                                    Text(venue.chefBio)
                                        .font(.system(size: 22, weight: .light))
                                        .multilineTextAlignment(.center)
                                        .foregroundColor(.secondary)
                                        .frame(maxWidth: 800)
                                }
                            }
                            .padding(35)
                            .frame(maxWidth: 900)
                            .background(RoundedRectangle(cornerRadius: 25).fill(.ultraThinMaterial))
                        }
                        .buttonStyle(.card)
                    }

                    // Photo Gallery - individual images are focusable
                    if !venue.gallery.isEmpty && venue.gallery.count > 1 {
                        VStack(alignment: .leading, spacing: 20) {
                            Label("Gallery", systemImage: "photo.on.rectangle.angled")
                                .font(.system(size: 26, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 60)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 25) {
                                    ForEach(venue.gallery, id: \.self) { imageUrl in
                                        Button(action: {}) {
                                            AsyncImage(url: URL(string: imageUrl)) { phase in
                                                if let image = phase.image {
                                                    image.resizable().aspectRatio(contentMode: .fill)
                                                } else {
                                                    Color.gray.opacity(0.2)
                                                }
                                            }
                                            .frame(width: 400, height: 280)
                                            .clipShape(RoundedRectangle(cornerRadius: 20))
                                        }
                                        .buttonStyle(.card)
                                    }
                                }
                                .padding(.horizontal, 60)
                            }
                        }
                    }

                    Spacer(minLength: 80)
                }
                .padding(.top, 40)
            }
        }
        .preferredColorScheme(.light)
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
