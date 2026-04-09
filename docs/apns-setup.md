# APNs Setup For Notibel

## Apple Developer Setup

You need your own Apple Developer account assets for this app.

### Create the app identifier

- choose a bundle ID, for example `com.notibel.app`
- enable the `Push Notifications` capability for that App ID

### Create an APNs auth key

- create a new key with `Apple Push Notifications service (APNs)` enabled
- download the `.p8` file once
- record the `Key ID`
- record your `Team ID`

The server uses:

- `NOTIBEL_APNS_KEY_PATH`
- `NOTIBEL_APNS_KEY_ID`
- `NOTIBEL_APNS_TEAM_ID`
- `NOTIBEL_APNS_BUNDLE_ID`

## Environment Choice

Set:

- `NOTIBEL_APNS_ENV=development` for local debug builds on a physical device
- `NOTIBEL_APNS_ENV=production` for TestFlight and App Store builds

Do not mix the wrong APNs environment with the wrong app build. The device token is environment-specific.

## iOS App Requirements

The app needs to:

1. ask for notification authorization
2. call `registerForRemoteNotifications()`
3. receive the device token
4. send that token to `PUT /v1/devices/{installationId}`

For the first MVP, normal alert pushes are enough. Background remote notifications can wait until the app needs silent refresh behavior.

## Suggested Server Secret Layout

```text
secrets/
  AuthKey_XXXXXXXXXX.p8
```

`.env` example:

```dotenv
NOTIBEL_APNS_KEY_PATH=/secrets/AuthKey_XXXXXXXXXX.p8
NOTIBEL_APNS_KEY_ID=XXXXXXXXXX
NOTIBEL_APNS_TEAM_ID=TEAMID1234
NOTIBEL_APNS_BUNDLE_ID=com.notibel.app
NOTIBEL_APNS_ENV=development
```

## Testing Sequence

1. install the development build on a physical iPhone
2. approve notification permission
3. confirm the device token registers successfully with Notibel
4. publish a test event with `./notify.sh "Test" "Hello from Notibel"`
5. verify the push alert appears and opens into the app

## Failure Modes To Expect

### `BadDeviceToken`

Usually means:

- wrong APNs environment
- stale token
- wrong bundle ID

### Push accepted but not visible

Usually means:

- notifications disabled on the phone
- app capability or provisioning issue
- alert payload is malformed

### Push never sent

Usually means:

- incomplete `NOTIBEL_APNS_*` config
- server cannot reach Apple over HTTPS
- bad `.p8` key path or key metadata
