#!/usr/bin/env ruby

require "fileutils"
require "pathname"
require "xcodeproj"

ROOT = Pathname.new(__dir__).join("..").expand_path
IOS_ROOT = ROOT.join("ios")
PROJECT_PATH = IOS_ROOT.join("Notibel.xcodeproj")

FileUtils.rm_rf(PROJECT_PATH)

project = Xcodeproj::Project.new(PROJECT_PATH.to_s)
project.root_object.attributes["LastSwiftMigration"] = "9999"

target = project.new_target(:application, "Notibel", :ios, "17.0")

target.build_configurations.each do |config|
  settings = config.build_settings
  settings["PRODUCT_BUNDLE_IDENTIFIER"] = "com.notibel.app"
  settings["PRODUCT_NAME"] = "Notibel"
  settings["MARKETING_VERSION"] = "0.1.0"
  settings["CURRENT_PROJECT_VERSION"] = "1"
  settings["SWIFT_VERSION"] = "5.0"
  settings["INFOPLIST_KEY_CFBundleDisplayName"] = "Notibel"
  settings["INFOPLIST_KEY_NSUserNotificationsUsageDescription"] = "Notibel sends notifications when your coding agents and automations complete work."
  settings["INFOPLIST_KEY_UILaunchStoryboardName"] = "LaunchScreen"
  settings["GENERATE_INFOPLIST_FILE"] = "YES"
  settings["ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME"] = "AccentColor"
  settings["ASSETCATALOG_COMPILER_APPICON_NAME"] = ""
  settings["CODE_SIGN_STYLE"] = "Automatic"
  settings["CODE_SIGN_ENTITLEMENTS"] = "Notibel/Notibel.entitlements"
  settings["DEVELOPMENT_TEAM"] = ""
  settings["TARGETED_DEVICE_FAMILY"] = "1"
  settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
  settings["SWIFT_EMIT_LOC_STRINGS"] = "YES"
end

project.build_configurations.each do |config|
  config.build_settings["IPHONEOS_DEPLOYMENT_TARGET"] = "17.0"
end

target_attributes = project.root_object.attributes["TargetAttributes"] ||= {}
target_attributes[target.uuid] = {
  "CreatedOnToolsVersion" => "26.4",
  "ProvisioningStyle" => "Automatic"
}

root_group = project.main_group.new_group("Notibel", "Notibel")
groups = {
  "App" => root_group.new_group("App", "App"),
  "Models" => root_group.new_group("Models", "Models"),
  "Services" => root_group.new_group("Services", "Services"),
  "Views" => root_group.new_group("Views", "Views"),
  "Resources" => root_group.new_group("Resources", "Resources")
}

source_files = [
  "App/NotibelApp.swift",
  "App/NotibelAppDelegate.swift",
  "App/PushBridge.swift",
  "App/AppModel.swift",
  "App/AppTab.swift",
  "App/AppRoute.swift",
  "App/FontRegistrar.swift",
  "Models/NotibelSettings.swift",
  "Models/NotibelEvent.swift",
  "Models/LoadState.swift",
  "Services/SettingsStore.swift",
  "Services/NotibelAPIClient.swift",
  "Views/RootView.swift",
  "Views/NotificationsView.swift",
  "Views/TopicDetailView.swift",
  "Views/SettingsView.swift",
  "Views/AddTopicSheet.swift",
  "Views/EventRowView.swift",
  "Views/EventDetailView.swift"
]

source_files.each do |relative_path|
  group_name, file_name = relative_path.split("/", 2)
  file_ref = groups.fetch(group_name).new_file(file_name)
  target.source_build_phase.add_file_reference(file_ref)
end

assets_ref = groups.fetch("Resources").new_file("Assets.xcassets")
target.resources_build_phase.add_file_reference(assets_ref)
font_ref = groups.fetch("Resources").new_file("Fonts/BerkeleyMono-Regular.ttf")
target.resources_build_phase.add_file_reference(font_ref)
launch_screen_ref = groups.fetch("Resources").new_file("LaunchScreen.storyboard")
target.resources_build_phase.add_file_reference(launch_screen_ref)
root_group.new_file("Notibel.entitlements")

project.save
