import SwiftUI
import MapKit
import CoreLocation
import AppKit

struct FulminazioneView: View {
    @ObservedObject var sinistro: Sinistro
    @StateObject private var locationManager = LocationManager()
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45.4642, longitude: 9.1900),
        span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1)
    )
    @State private var searchText = ""
    @State private var selectedPin: MKPlacemark?
    @State private var mapType: MKMapType = .standard
    @AppStorage("isMapExpanded") private var isMapExpanded: Bool = true
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Indirizzo e ricerca
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if let nomeAssicurato = sinistro.nomeAssicurato {
                            Text(nomeAssicurato)
                                .font(.headline)
                        }
                        
                        if let indirizzo = sinistro.indirizzoAssicurato {
                            Text(indirizzo)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.secondary)
                            TextField("Cerca indirizzo...", text: $searchText)
                                .textFieldStyle(.roundedBorder)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            Button(action: searchLocation) {
                                Text("Cerca")
                            }
                            .keyboardShortcut(.return, modifiers: [])
                        }
                    }
                }
                
                // Contenitore per mappa e tabella
                VStack(spacing: 12) {
                    // Header con controlli mappa
                    GroupBox {
                        HStack {
                            Picker("Tipo Mappa", selection: $mapType) {
                                Text("Standard").tag(MKMapType.standard)
                                Text("Satellite").tag(MKMapType.satellite)
                                Text("Ibrida").tag(MKMapType.hybrid)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 300)
                            .opacity(isMapExpanded ? 1 : 0)
                            
                            Spacer()
                            
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isMapExpanded.toggle()
                                }
                            }) {
                                Image(systemName: isMapExpanded ? "chevron.up" : "chevron.down")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isMapExpanded ? "Nascondi mappa" : "Mostra mappa")
                        }
                        .frame(height: 25)
                        
                        if isMapExpanded {
                            VStack(spacing: 8) {
                                // Mappa
                                MapViewRepresentable(
                                    region: $region,
                                    selectedPin: $selectedPin,
                                    mapType: mapType
                                )
                                .frame(height: 400)
                                .cornerRadius(6)
                                
                                // Coordinate
                                HStack {
                                    Text("Lat: \(region.center.latitude, specifier: "%.6f")")
                                    Spacer()
                                    Text("Long: \(region.center.longitude, specifier: "%.6f")")
                                }
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }
                    }
                    
                    // Tabella fulminazioni
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Analisi Fulminazioni")
                                    .font(.headline)
                                Spacer()
                                if let dataSinistro = sinistro.dataSinistro {
                                    Text(dataSinistro, formatter: dateFormatter)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Divider()
                            
                            FulminazioneTableView(dataSinistro: sinistro.dataSinistro ?? Date())
                        }
                    }
                }
            }
            .padding()
        }
        .onAppear {
            if let indirizzo = sinistro.indirizzoAssicurato, !indirizzo.isEmpty {
                searchText = indirizzo
                searchLocation()
            }
        }
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        formatter.locale = Locale(identifier: "it_IT")
        return formatter
    }
    
    private func searchLocation() {
        locationManager.geocode(searchText) { placemark in
            if let placemark = placemark {
                selectedPin = placemark
                region.center = placemark.coordinate
                region.span = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            }
        }
    }
}

// Aggiorniamo MapViewRepresentable per supportare il tipo di mappa
struct MapViewRepresentable: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var selectedPin: MKPlacemark?
    var mapType: MKMapType
    
    func makeNSView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.mapType = mapType
        
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        mapView.addGestureRecognizer(clickGesture)
        
        return mapView
    }
    
    func updateNSView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)
        mapView.mapType = mapType
        
        mapView.removeAnnotations(mapView.annotations)
        if let pin = selectedPin {
            let annotation = DraggableAnnotation()
            annotation.coordinate = pin.coordinate
            annotation.title = pin.title
            annotation.isDraggable = true
            mapView.addAnnotation(annotation)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapViewRepresentable
        
        init(_ parent: MapViewRepresentable) {
            self.parent = parent
        }
        
        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            let mapView = gesture.view as! MKMapView
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            
            // Crea un nuovo placemark
            let placemark = MKPlacemark(coordinate: coordinate)
            parent.selectedPin = placemark
            parent.region.center = coordinate
        }
        
        // Gestione del pin trascinabile
        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            let identifier = "DraggablePin"
            
            var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)
            if annotationView == nil {
                annotationView = MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                annotationView?.isDraggable = true
                annotationView?.canShowCallout = true
            } else {
                annotationView?.annotation = annotation
            }
            
            return annotationView
        }
        
        // Gestione degli eventi di trascinamento
        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .ending:
                if let newCoordinate = view.annotation?.coordinate {
                    // Aggiorna il placemark e la regione
                    let placemark = MKPlacemark(coordinate: newCoordinate)
                    parent.selectedPin = placemark
                    parent.region.center = newCoordinate
                }
            default:
                break
            }
        }
    }
}

// Classe personalizzata per l'annotazione trascinabile
class DraggableAnnotation: MKPointAnnotation {
    var isDraggable: Bool = true
}

// LocationManager per la geocodifica
class LocationManager: NSObject, ObservableObject {
    private let geocoder = CLGeocoder()
    
    func geocode(_ address: String, completion: @escaping (MKPlacemark?) -> Void) {
        geocoder.geocodeAddressString(address) { placemarks, error in
            guard let placemark = placemarks?.first else {
                completion(nil)
                return
            }
            completion(MKPlacemark(placemark: placemark))
        }
    }
}

// Vista per la tabella delle fulminazioni
struct FulminazioneTableView: View {
    let dataSinistro: Date
    @State private var fulminazioneModel: FulminazioneModel
    
    init(dataSinistro: Date) {
        self.dataSinistro = dataSinistro
        _fulminazioneModel = State(initialValue: FulminazioneModel(
            coordinate: CLLocationCoordinate2D(),
            indirizzo: "",
            dataSinistro: dataSinistro
        ))
    }
    
    var body: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 0) {
                // Header
                HStack(spacing: 0) {
                    Text("Data")
                        .frame(width: 150)
                        .background(Color.secondary.opacity(0.2))
                    ForEach(["1,5 KM", "3 KM", "5 KM", "10 KM"], id: \.self) { header in
                        Text(header)
                            .frame(width: 100)
                            .background(Color.secondary.opacity(0.2))
                    }
                }
                
                // Rows
                ForEach(fulminazioneModel.dateAnalisi) { data in
                    HStack(spacing: 0) {
                        Text(formatDate(data.data))
                            .frame(width: 150)
                            .background(data.data == dataSinistro ? Color.blue.opacity(0.1) : Color.clear)
                        
                        ForEach([data.entro1km, data.entro3km, data.entro5km, data.entro10km], id: \.self) { value in
                            Image(systemName: value ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(value ? .green : .secondary)
                                .frame(width: 100)
                        }
                    }
                }
            }
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        DateUtils.formatMedium(date)
    }
} 