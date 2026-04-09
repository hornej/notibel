enum AppRoute: Hashable {
    case topic(String)
    case event(NotibelEvent)
    case eventReference(NotibelEventReference)
}
