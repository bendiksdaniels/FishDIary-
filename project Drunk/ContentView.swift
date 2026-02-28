
import SwiftUI
import PhotosUI
import Combine
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Cross-platform image helpers
struct PhotoImageView: View {
    let data: Data
    var isThumbnail: Bool = true

    var body: some View {
        #if canImport(UIKit)
        if let img = UIImage(data: data) {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: isThumbnail ? 56 : nil, height: isThumbnail ? 56 : nil)
                .clipped()
        }
        #elseif canImport(AppKit)
        if let img = NSImage(data: data) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: isThumbnail ? 56 : nil, height: isThumbnail ? 56 : nil)
                .clipped()
        }
        #endif
    }
}

// MARK: - Models

enum FishSpecies: String, CaseIterable, Codable, Hashable {
    case pike = "Pike"
    case perch = "Perch"
    case bass = "Bass"
    case trout = "Trout"
    case salmon = "Salmon"
    case carp = "Carp"
}

struct FishingEntry: Identifiable, Codable, Hashable {
    static func == (lhs: FishingEntry, rhs: FishingEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    let id: UUID
    var date: Date
    var species: FishSpecies

    /// Measured weight. 0 means "none"
    var weightKg: Double

    /// Measured length. nil means "none"
    var lengthCm: Double?

    var photoData: Data?

    var bait: String?
    var baitImages: [Data]

    // Recalculated estimates
    var estimatedAgeYears: Double
    var rarityScore: Double

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        species: FishSpecies,
        weightKg: Double,
        lengthCm: Double? = nil,
        photoData: Data? = nil,
        bait: String? = nil,
        baitImages: [Data] = []
    ) {
        self.id = id
        self.date = date
        self.species = species
        self.weightKg = max(0, weightKg)
        self.lengthCm = (lengthCm ?? 0) > 0 ? lengthCm : nil
        self.photoData = photoData
        self.bait = bait
        self.baitImages = baitImages

        // ✅ Recalculate estimates from the best available input
        if self.weightKg > 0 {
            self.estimatedAgeYears = FishEstimator.estimateAge(species: species, weightKg: self.weightKg)
            self.rarityScore = FishEstimator.estimateRarity(species: species, weightKg: self.weightKg)
        } else if let l = self.lengthCm, l > 0 {
            let estW = FishEstimator.estimateWeight(species: species, lengthCm: l)
            self.estimatedAgeYears = FishEstimator.estimateAge(species: species, lengthCm: l)
            self.rarityScore = FishEstimator.estimateRarity(species: species, weightKg: estW)
        } else {
            self.estimatedAgeYears = 0
            self.rarityScore = 0
        }
    }

    var estimatedWeightFromLength: Double? {
        guard weightKg <= 0, let l = lengthCm, l > 0 else { return nil }
        return FishEstimator.estimateWeight(species: species, lengthCm: l)
    }
}

// MARK: - Estimator (simple placeholder logic you can improve later)

enum FishEstimator {
    static func estimateWeight(species: FishSpecies, lengthCm: Double) -> Double {
        // super simple placeholder: weight ~ k * length^3
        let k: Double
        switch species {
        case .pike:   k = 0.000020
        case .perch:  k = 0.000018
        case .bass:   k = 0.000019
        case .trout:  k = 0.000017
        case .salmon: k = 0.000022
        case .carp:   k = 0.000021
        }
        let w = k * pow(max(0, lengthCm), 3)
        return max(0, min(999.99, w))
    }

    static func estimateAge(species: FishSpecies, weightKg: Double) -> Double {
        // placeholder: age grows with log(weight)
        let base: Double
        switch species {
        case .pike: base = 2.2
        case .perch: base = 1.7
        case .bass: base = 2.0
        case .trout: base = 1.8
        case .salmon: base = 2.3
        case .carp: base = 2.5
        }
        let age = base * log10(max(0.1, weightKg * 10))
        return max(0, min(40, age))
    }

    static func estimateAge(species: FishSpecies, lengthCm: Double) -> Double {
        // placeholder: age ~ length / factor
        let factor: Double
        switch species {
        case .pike: factor = 12
        case .perch: factor = 10
        case .bass: factor = 11
        case .trout: factor = 10
        case .salmon: factor = 13
        case .carp: factor = 14
        }
        return max(0, min(40, lengthCm / factor))
    }

    static func estimateRarity(species: FishSpecies, weightKg: Double) -> Double {
        // placeholder rarity 0-10
        let speciesBoost: Double
        switch species {
        case .pike: speciesBoost = 1.0
        case .perch: speciesBoost = 0.6
        case .bass: speciesBoost = 0.9
        case .trout: speciesBoost = 1.2
        case .salmon: speciesBoost = 1.4
        case .carp: speciesBoost = 0.8
        }
        let score = min(10, max(0, speciesBoost * sqrt(max(0, weightKg)) * 2))
        return score
    }
}

// MARK: - ViewModel

final class DiaryViewModel: ObservableObject {
    
    @Published var entries: [FishingEntry] = []

    func addEntry(species: FishSpecies, weightKg: Double?, lengthCm: Double?, photoData: Data?) {
        let w = max(0, weightKg ?? 0)
        let l = (lengthCm ?? 0) > 0 ? lengthCm : nil
        let entry = FishingEntry(species: species, weightKg: w, lengthCm: l, photoData: photoData)
        entries.insert(entry, at: 0)
    }

    func remove(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
    }

    func removeEntry(id: UUID) {
        entries.removeAll { $0.id == id }
    }

    func updateWeight(entryID: UUID, weightKg: Double) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let old = entries[idx]
        let updated = FishingEntry(
            id: old.id,
            date: old.date,
            species: old.species,
            weightKg: max(0, weightKg),
            lengthCm: old.lengthCm,
            photoData: old.photoData,
            bait: old.bait,
            baitImages: old.baitImages
        )
        entries[idx] = updated
    }

    func updateLength(entryID: UUID, lengthCm: Double?) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        let old = entries[idx]
        let l = (lengthCm ?? 0) > 0 ? lengthCm : nil
        let updated = FishingEntry(
            id: old.id,
            date: old.date,
            species: old.species,
            weightKg: old.weightKg,
            lengthCm: l,
            photoData: old.photoData,
            bait: old.bait,
            baitImages: old.baitImages
        )
        entries[idx] = updated
    }

    func updatePhoto(entryID: UUID, photoData: Data?) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[idx].photoData = photoData
    }

    func updateBait(entryID: UUID, bait: String?) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[idx].bait = bait
    }

    func addBaitImage(entryID: UUID, imageData: Data) {
        guard let idx = entries.firstIndex(where: { $0.id == entryID }) else { return }
        entries[idx].baitImages.append(imageData)
    }
}

// MARK: - Input Sanitizer (3 digit integer part)

private func sanitizeNumberText(_ input: String, maxIntegerDigits: Int, maxFractionDigits: Int) -> String {
    let normalized = input.replacingOccurrences(of: ",", with: ".")
    let allowed = normalized.filter { $0.isNumber || $0 == "." }

    // only 1 dot
    var out = ""
    var dotUsed = false
    for ch in allowed {
        if ch == "." {
            if dotUsed { continue }
            dotUsed = true
            out.append(ch)
        } else {
            out.append(ch)
        }
    }

    let parts = out.split(separator: ".", omittingEmptySubsequences: false)
    let intRaw = parts.first.map(String.init) ?? ""
    let fracRaw = parts.count > 1 ? String(parts[1]) : ""

    let intPart = String(intRaw.prefix(maxIntegerDigits))
    if dotUsed {
        let fracPart = String(fracRaw.prefix(maxFractionDigits))
        if intRaw.isEmpty {
            return "." + fracPart
        }
        return intPart + "." + fracPart
    } else {
        return intPart
    }
}

// MARK: - Views

struct ContentView: View {
    @StateObject private var vm = DiaryViewModel()
    @State private var showHistory = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                AddEntryForm { species, weight, length, photo in
                    vm.addEntry(species: species, weightKg: weight, lengthCm: length, photoData: photo)
                }
                .padding(.top, 8)
                .padding(.horizontal)

                Spacer(minLength: 0)
            }
            .navigationTitle("Add Catch")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showHistory = true
                    } label: {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink {
                        ExtraScreenView(vm: vm)
                    } label: {
                        Label("More", systemImage: "square.grid.2x2")
                    }
                }
            }
            .navigationDestination(isPresented: $showHistory) {
                PreviouslyCaughtFishView(vm: vm)
            }
        }
    }
}

struct AddEntryForm: View {
    var onAdd: (FishSpecies, Double?, Double?, Data?) -> Void

    @State private var species: FishSpecies = .pike
    @State private var weightText: String = ""
    @State private var lengthText: String = ""
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var photoData: Data? = nil

    var weightValue: Double? {
        let t = weightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return Double(t)
    }

    var lengthValue: Double? {
        let t = lengthText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        return Double(t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Species", selection: $species) {
                    ForEach(FishSpecies.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.menu)

                Spacer()

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(photoData == nil ? "Photo" : "Change", systemImage: "camera.fill")
                }
                .onChange(of: photoItem) { newItem in
                    Task {
                        guard let item = newItem else { return }
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            await MainActor.run {
                                photoData = data
                            }
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weight (kg)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            TextField("0", text: $weightText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity)
                                .layoutPriority(1)
                                .onChange(of: weightText) { newValue in
                                    let s = sanitizeNumberText(newValue, maxIntegerDigits: 3, maxFractionDigits: 2)
                                    if s != newValue { weightText = s }
                                }

                            Text("kg")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Length (cm)")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: 6) {
                            TextField("0", text: $lengthText)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: .infinity)
                                .layoutPriority(1)
                                .onChange(of: lengthText) { newValue in
                                    let s = sanitizeNumberText(newValue, maxIntegerDigits: 3, maxFractionDigits: 1)
                                    if s != newValue { lengthText = s }
                                }

                            Text("cm")
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Button {
                    onAdd(species, weightValue, lengthValue, photoData)
                    weightText = ""
                    lengthText = ""
                    photoData = nil
                    photoItem = nil
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled((weightValue ?? 0) <= 0 && (lengthValue ?? 0) <= 0 && photoData == nil)
            }
        }
        .padding(.vertical, 8)
    }
}

struct EntryRow: View {
    let entry: FishingEntry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "fish.fill")
                .font(.title3)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.species.rawValue)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 12) {
                    if entry.weightKg > 0 {
                        Text("\(entry.weightKg, specifier: "%.2f") kg")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if let est = entry.estimatedWeightFromLength {
                        Text("\(est, specifier: "%.2f") kg")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let l = entry.lengthCm {
                        Text("\(l, specifier: "%.1f") cm")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct EntryDetailView: View {
    @ObservedObject var vm: DiaryViewModel
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var editedWeightText: String = ""
    @State private var editedLengthText: String = ""

    @State private var photoItem: PhotosPickerItem? = nil

    private var entry: FishingEntry? {
        vm.entries.first(where: { $0.id == entryID })
    }

    var body: some View {
        Group {
            if let entry = entry {
                List {
                    Section("Photo") {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(entry.photoData == nil ? "Add Photo" : "Change Photo", systemImage: "camera.fill")
                        }
                        .onChange(of: photoItem) { newItem in
                            Task {
                                guard let item = newItem else { return }
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        vm.updatePhoto(entryID: entry.id, photoData: data)
                                    }
                                }
                            }
                        }

                        if let data = entry.photoData, let uiImage = UIImage(data: data) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                                .padding(.top, 6)
                        }
                    }

                    Section("Measurements") {
                        TextField("Measured Weight (kg)", text: $editedWeightText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editedWeightText) { newValue in
                                let s = sanitizeNumberText(newValue, maxIntegerDigits: 3, maxFractionDigits: 2)
                                if s != newValue { editedWeightText = s }
                            }

                        Button("Save Weight") {
                            let t = editedWeightText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                            if t.isEmpty {
                                vm.updateWeight(entryID: entry.id, weightKg: 0)
                            } else if let w = Double(t), w >= 0, w <= 999.99 {
                                vm.updateWeight(entryID: entry.id, weightKg: w)
                            }
                        }

                        TextField("Length (cm)", text: $editedLengthText)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: editedLengthText) { newValue in
                                let s = sanitizeNumberText(newValue, maxIntegerDigits: 3, maxFractionDigits: 1)
                                if s != newValue { editedLengthText = s }
                            }

                        Button("Save Length") {
                            let t = editedLengthText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
                            if t.isEmpty {
                                vm.updateLength(entryID: entry.id, lengthCm: nil)
                            } else if let l = Double(t), l >= 0, l <= 999.9 {
                                vm.updateLength(entryID: entry.id, lengthCm: l)
                            }
                        }

                        Divider()

                        if entry.weightKg > 0 {
                            LabeledContent("Weight", value: "\(entry.weightKg, default: "%.2f") kg")
                        } else if let est = entry.estimatedWeightFromLength {
                            LabeledContent("Weight", value: "\(est, default: "%.2f") kg (EST.)")
                        }

                        if let l = entry.lengthCm {
                            LabeledContent("Length", value: "\(l, default: "%.1f") cm")
                        }

                        if entry.estimatedAgeYears > 0 {
                            LabeledContent("Estimated Age", value: "\(entry.estimatedAgeYears, default: "%.1f") years")
                        }

                        if entry.rarityScore > 0 {
                            LabeledContent("Rarity", value: "\(entry.rarityScore, default: "%.1f")")
                        }
                    }

                    Section("Bait") {
                        NavigationLink {
                            BaitDetailView(vm: vm, entryID: entry.id)
                        } label: {
                            Text(entry.bait?.isEmpty == false ? "Edit Bait Details" : "Add Bait Details")
                        }

                        if let bait = entry.bait, !bait.isEmpty {
                            Text("Bait used: \(bait)")
                                .foregroundColor(.secondary)
                        }
                    }

                    Section {
                        Button(role: .destructive) {
                            vm.removeEntry(id: entry.id)
                            dismiss()
                        } label: {
                            Label("Delete Catch", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .navigationTitle("Catch Details")
                .onAppear {
                    editedWeightText = entry.weightKg > 0 ? String(format: "%.2f", entry.weightKg) : ""
                    editedLengthText = entry.lengthCm.map { String(format: "%.1f", $0) } ?? ""
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Catch not found").font(.headline)
                }
                .navigationTitle("Catch Details")
            }
        }
    }
}

struct BaitDetailView: View {
    @ObservedObject var vm: DiaryViewModel
    let entryID: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var baitText: String = ""
    @State private var pickerItem: PhotosPickerItem? = nil

    private var entry: FishingEntry? {
        vm.entries.first(where: { $0.id == entryID })
    }

    var body: some View {
        Group {
            if let entry = entry {
                Form {
                    Section("Bait") {
                        TextField("Bait used", text: $baitText)
                            .textInputAutocapitalization(.words)

                        Button("Save Bait") {
                            let t = baitText.trimmingCharacters(in: .whitespacesAndNewlines)
                            vm.updateBait(entryID: entry.id, bait: t.isEmpty ? nil : t)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Section {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            Label("Add Bait Image", systemImage: "camera.fill")
                        }
                        .onChange(of: pickerItem) { newItem in
                            Task {
                                guard let item = newItem else { return }
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    await MainActor.run {
                                        vm.addBaitImage(entryID: entry.id, imageData: data)
                                    }
                                }
                            }
                        }
                    }

                    if !entry.baitImages.isEmpty {
                        Section("Bait Images") {
                            ScrollView(.horizontal, showsIndicators: true) {
                                HStack(spacing: 12) {
                                    ForEach(entry.baitImages.indices, id: \.self) { i in
                                        if let img = UIImage(data: entry.baitImages[i]) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 120, height: 120)
                                                .clipped()
                                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                }
                .navigationTitle("Bait Details")
                .onAppear {
                    baitText = entry.bait ?? ""
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.largeTitle)
                    Text("Catch not found").font(.headline)
                }
                .navigationTitle("Bait Details")
            }
        }
    }
}

struct PreviouslyCaughtFishView: View {
    @ObservedObject var vm: DiaryViewModel

    var body: some View {
        List {
            if vm.entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "fish.fill").font(.largeTitle)
                    Text("No catches yet").font(.headline)
                    Text("Add a catch from the Add Catch screen.")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 260)
                .listRowSeparator(.hidden)
            } else {
                ForEach(vm.entries) { entry in
                    NavigationLink {
                        EntryDetailView(vm: vm, entryID: entry.id)
                    } label: {
                        EntryRow(entry: entry)
                    }
                }
                .onDelete(perform: vm.remove)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Previously Caught Fish")
    }
}


struct ExtraScreenView: View {
    @ObservedObject var vm: DiaryViewModel

    var body: some View {
        List {
            Section {
                Text("New screen placeholder")
                Text("Tell me what you want on this screen and I’ll build it.")
                    .foregroundStyle(.secondary)
            }

            Section("Quick Stats") {
                LabeledContent("Total Catches", value: "\(vm.entries.count)")
            }
        }
        .navigationTitle("More")
        .listStyle(.insetGrouped)
    }
}
