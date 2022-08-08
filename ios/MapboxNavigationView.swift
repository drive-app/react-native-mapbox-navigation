import MapboxCoreNavigation
import MapboxNavigation
import MapboxDirections

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

  @objc var waypoints: NSArray<NSArray> = [] {
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

    let waypointObjects: [Waypoint] = []
    for wp in waypoints {
      waypointObjects.append(
        Waypoint(coordinate: CLLocationCoordinate2D(latitude: wp[1] as! CLLocationDegrees, longitude: wp[0] as! CLLocationDegrees))
      )
    }

    let options = NavigationRouteOptions(waypoints: waypointObjects, profileIdentifier: .automobileAvoidingTraffic)
    options.locale = Locale(identifier: localeIdentifier)

    Directions.shared.calculate(options) { [weak self] (_, result) in
      guard let strongSelf = self, let parentVC = strongSelf.parentViewController else {
        return
      }
      
      switch result {
        case .failure(let error):
          strongSelf.onError!(["message": error.localizedDescription])
        case .success(let response):
          guard let weakSelf = self else {
            return
          }

          let navigationService = MapboxNavigationService(routeResponse: response, routeIndex: 0, routeOptions: options, simulating: strongSelf.shouldSimulateRoute ? .always : .never)
          let navigationOptions = NavigationOptions(styles: [DriveNavStyle()], navigationService: navigationService)
          let vc = NavigationViewController(for: response, routeIndex: 0, routeOptions: options, navigationOptions: navigationOptions)

          vc.showsEndOfRouteFeedback = strongSelf.showsEndOfRouteFeedback
          StatusView.appearance().isHidden = strongSelf.hideStatusView

          NavigationSettings.shared.voiceMuted = strongSelf.mute;
          
          vc.delegate = strongSelf
        
          parentVC.addChild(vc)
          strongSelf.addSubview(vc.view)
          vc.view.frame = strongSelf.bounds
          vc.didMove(toParent: parentVC)
          strongSelf.navViewController = vc
      }
      
      strongSelf.embedding = false
      strongSelf.embedded = true
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