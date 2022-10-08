import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections
import Polyline
import Turf

open class DriveNavStyle: NightStyle {
    public required init() {
        super.init()
        mapStyleURL = URL(string: "mapbox://styles/driveapp/cl28en201000415mkpdop4fj9")!
        previewMapStyleURL = mapStyleURL
    }
    
    open override func apply() {
        super.apply()
        let phoneTraitCollection = UITraitCollection(userInterfaceIdiom: .phone)
        
        TopBannerView.appearance(for: phoneTraitCollection).backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        BottomBannerView.appearance(for: phoneTraitCollection).backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        InstructionsBannerView.appearance(for: phoneTraitCollection).backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
        BottomPaddingView.appearance(for: phoneTraitCollection).backgroundColor = #colorLiteral(red: 0, green: 0, blue: 0, alpha: 1)
    }
}



// // adapted from https://pspdfkit.com/blog/2017/native-view-controllers-and-react-native/ and https://github.com/mslabenyak/react-native-mapbox-navigation/blob/master/ios/Mapbox/MapboxNavigationView.swift
extension UIView {
  var parentViewController: UIViewController? {
    var parentResponder: UIResponder? = self
    while parentResponder != nil {
      parentResponder = parentResponder!.next
      if let viewController = parentResponder as? UIViewController {
        return viewController
      }
    }
    return nil
  }
}

class MapboxNavigationView: UIView, NavigationViewControllerDelegate {
  weak var navViewController: NavigationViewController?
  var embedded: Bool
  var embedding: Bool
  var routeResults: Dictionary<Int, RouteResponse>

  @objc var waypoints: [[NSArray]] = [] {
    didSet { setNeedsLayout() }
  }
  
  @objc var shouldSimulateRoute: Bool = false
  @objc var showsEndOfRouteFeedback: Bool = false
  @objc var hideStatusView: Bool = false
  @objc var mute: Bool = false
  @objc var localeIdentifier: String = "en_US"
  
  @objc var onLocationChange: RCTDirectEventBlock?
  @objc var onRouteProgressChange: RCTDirectEventBlock?
  @objc var onError: RCTDirectEventBlock?
  @objc var onCancelNavigation: RCTDirectEventBlock?
  @objc var onArrive: RCTDirectEventBlock?
  
  override init(frame: CGRect) {
    self.embedded = false
    self.embedding = false
    self.routeResults = [Int:RouteResponse]()
    super.init(frame: frame)
  }
  
  required init?(coder aDecoder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func layoutSubviews() {
    super.layoutSubviews()
    
    if (navViewController == nil && !embedding && !embedded) {
      embed()
    } else {
      navViewController?.view.frame = bounds
    }
  }
  
  override func removeFromSuperview() {
    super.removeFromSuperview()
    // cleanup and teardown any existing resources
    self.navViewController?.removeFromParent()
  }
  
  private func embed() {
    guard waypoints.count >= 2 else { return }
    
    embedding = true
    
    print("embedding with \(waypoints.count) waypoints")
    var waypointObjects: [Waypoint] = []
    for wp in waypoints {
      let w = wp as! NSArray
      var newWaypoint = Waypoint(coordinate: CLLocationCoordinate2D(latitude: w[1] as! CLLocationDegrees, longitude: w[0] as! CLLocationDegrees))
      newWaypoint.separatesLegs = false
      waypointObjects.append(
        newWaypoint
      )
    }


    // groups of 25 or less waypoints
    var waypointGroups: [[Waypoint]] = [];
    for waypointIndex in 0...(waypointObjects.count - 1) {
        let groupIndex = (waypointIndex/25)
        print("waypointIndex: \(waypointIndex), groupIndex: \(groupIndex)")
        if(waypointGroups.count - 1 < groupIndex){
            waypointGroups.append([])
        }
        waypointGroups[groupIndex].append(waypointObjects[waypointIndex])
    }
      
    // check if any of the groups have only one waypoint
    for waypointGroupIndex in 0...(waypointGroups.count - 1) {
        if(waypointGroups[waypointGroupIndex].count < 2) {
            // remove the last waypoint from the previous group and place it before the lonley waypoint in the current waypoint group
            let newFirstWaypoint: Waypoint = waypointGroups[waypointGroupIndex - 1].remove(at: 24)
            waypointGroups[waypointGroupIndex].insert(newFirstWaypoint, at: 0)
            print("handled lonelyc waypoint edgecase")
        }
    }

    print("Generated \(waypointGroups.count) waypoint groups.")

    // fetch directions for each group of 25 (or less for the last group) waypoints
    print("Generating async dispatch group")
    let asyncDispatchGroup = DispatchGroup()

    for waypointGroupIndex in 0...(waypointGroups.count - 1) {
      asyncDispatchGroup.enter()
      let options = NavigationRouteOptions(waypoints: waypointGroups[waypointGroupIndex], profileIdentifier: .automobileAvoidingTraffic)
      options.locale = Locale(identifier: localeIdentifier)
      Directions.shared.calculate(options) { [weak self] (_, result) in
        guard let strongSelf = self, let parentVC = strongSelf.parentViewController else {
          return
        }
        
        switch result {
          case .failure(let error):
            print("Waypoint Group Index \(waypointGroupIndex) (with \(waypointGroups[waypointGroupIndex].count) waypoints) failure.")
            print(error.localizedDescription)
            strongSelf.onError!(["message": error.localizedDescription])
            
          case .success(let response):
            guard let weakSelf = self else {
              return
            }
            print("Waypoint Group Index \(waypointGroupIndex) success.")
            strongSelf.routeResults[waypointGroupIndex] = response
        }
        
        strongSelf.embedding = false
        strongSelf.embedded = true
        print("Waypoint Group Index \(waypointGroupIndex) complete.")
        asyncDispatchGroup.leave()
      }
    }
    
    asyncDispatchGroup.notify(queue: .main) {
        print("Async Dispatch Group Notified Complete")

        print("initialising compiled route response variables.")
        let firstRouteResponse: RouteResponse = self.routeResults[0]!
        var compiledRoutes: [Route] = [Route]()
        var compiledLegs: [RouteLeg] = [RouteLeg]()
        var compiledShape: LineString = LineString([])
        var compiledDistance: CLLocationDistance = 0
        var compiledExpectedTravelTime: TimeInterval = 0
        var compiledOptions: RouteOptions = NavigationRouteOptions(
            waypoints: waypointObjects,
            profileIdentifier: .automobileAvoidingTraffic
        )
        compiledOptions.locale = Locale(identifier: self.localeIdentifier)

        // compile the routes
        print("Compiling the route response legs")
        
        for key in 0...(Array(self.routeResults.keys).count - 1) {
            print("routeLeg key \(key)")
            // get a list of the first routes from all the route responses
            for routeLeg in self.routeResults[key]!.routes![0].legs {
                compiledLegs.append(routeLeg)
            }
            // append the coordinates to the compiled shape for the line string
            for coordinate in self.routeResults[key]!.routes![0].shape!.coordinates {
                compiledShape.coordinates.append(coordinate)
            }
            
            // incremenet the compiled distance
            compiledDistance += self.routeResults[key]!.routes![0].distance
            
            // increment the compiled travel time
            compiledExpectedTravelTime += self.routeResults[key]!.routes![0].expectedTravelTime
        }
        
        print("Instantiating the final route from thce compiled legs")
        compiledRoutes.append(Route(
            legs: compiledLegs,
            shape: compiledShape,
            distance: compiledDistance,
            expectedTravelTime: compiledExpectedTravelTime
        ))
        
        print("Instantiating route response")
        let compiledRouteResponse: RouteResponse = RouteResponse(
            httpResponse: firstRouteResponse.httpResponse,
            identifier: firstRouteResponse.identifier,
            routes: compiledRoutes,
            waypoints: waypointObjects,
            options: .route(compiledOptions),
            credentials: firstRouteResponse.credentials
        )

        print("Completed compiled route response, rendering nav")  
        guard let parentVC = self.parentViewController else {
            return
        }
         
        let navigationService = MapboxNavigationService(routeResponse: compiledRouteResponse, routeIndex: 0, routeOptions: compiledOptions, simulating: self.shouldSimulateRoute ? .always : .never)
        let navigationOptions = NavigationOptions(styles: [DriveNavStyle()], navigationService: navigationService)
        let vc = NavigationViewController(for: compiledRouteResponse, routeIndex: 0, routeOptions: compiledOptions, navigationOptions: navigationOptions)

        vc.showsEndOfRouteFeedback = self.showsEndOfRouteFeedback
        StatusView.appearance().isHidden = self.hideStatusView

        NavigationSettings.shared.voiceMuted = self.mute;

        vc.delegate = self

        parentVC.addChild(vc)
        self.addSubview(vc.view)
        vc.view.frame = self.bounds
        vc.didMove(toParent: parentVC)
        vc.floatingButtons = nil
        self.navViewController = vc
      
    }
  }
  
  func navigationViewController(_ navigationViewController: NavigationViewController, didUpdate progress: RouteProgress, with location: CLLocation, rawLocation: CLLocation) {
    onLocationChange?(["longitude": location.coordinate.longitude, "latitude": location.coordinate.latitude])
    onRouteProgressChange?(["distanceTraveled": progress.distanceTraveled,
                            "durationRemaining": progress.durationRemaining,
                            "fractionTraveled": progress.fractionTraveled,
                            "distanceRemaining": progress.distanceRemaining])
  }
  
  func navigationViewControllerDidDismiss(_ navigationViewController: NavigationViewController, byCanceling canceled: Bool) {
    if (!canceled) {
      return;
    }
    onCancelNavigation?(["message": ""]);
  }
  
  func navigationViewController(_ navigationViewController: NavigationViewController, didArriveAt waypoint: Waypoint) -> Bool {
    onArrive?(["message": ""]);
    return true;
  }
}
