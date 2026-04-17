package notifier

import (
	"context"
	"io"
	"log"
	"testing"

	"github.com/hornej/notibel/internal/apns"
	"github.com/hornej/notibel/internal/store"
)

func TestPublishFansOutToRegisteredDevices(t *testing.T) {
	t.Parallel()

	eventStore := newTestStore(t)
	for _, registration := range []store.DeviceRegistration{
		{InstallationID: "phone-1", DeviceToken: "token-1", Topics: []string{"codex"}},
		{InstallationID: "phone-2", DeviceToken: "token-2", Topics: []string{"codex"}},
		{InstallationID: "phone-3", DeviceToken: "token-3", Topics: []string{"claude"}},
	} {
		if _, err := eventStore.UpsertDevice(registration); err != nil {
			t.Fatalf("upsert device: %v", err)
		}
	}

	apnsClient := &stubAPNSClient{}
	service := New(eventStore, apnsClient, log.New(io.Discard, "", 0), 10)

	result, err := service.Publish(context.Background(), "codex", PublishRequest{
		Title:   "Codex",
		Message: "Finished the task.",
	})
	if err != nil {
		t.Fatalf("publish: %v", err)
	}

	if result.RegisteredDevices != 2 {
		t.Fatalf("registered devices = %d, want 2", result.RegisteredDevices)
	}
	if result.Delivered != 2 {
		t.Fatalf("delivered = %d, want 2", result.Delivered)
	}
	if len(apnsClient.sentDeviceTokens) != 2 {
		t.Fatalf("sent device count = %d, want 2", len(apnsClient.sentDeviceTokens))
	}
}

func TestPublishDropsUnregisteredDevices(t *testing.T) {
	t.Parallel()

	eventStore := newTestStore(t)
	if _, err := eventStore.UpsertDevice(store.DeviceRegistration{
		InstallationID: "phone-1",
		DeviceToken:    "token-1",
		Topics:         []string{"codex"},
	}); err != nil {
		t.Fatalf("upsert device: %v", err)
	}

	apnsClient := &stubAPNSClient{
		errorsByToken: map[string]error{
			"token-1": &apns.ErrUnregistered{Reason: "Unregistered"},
		},
	}
	service := New(eventStore, apnsClient, log.New(io.Discard, "", 0), 10)

	result, err := service.Publish(context.Background(), "codex", PublishRequest{
		Message: "Finished the task.",
	})
	if err != nil {
		t.Fatalf("publish: %v", err)
	}

	if result.RegisteredDevices != 1 {
		t.Fatalf("registered devices = %d, want 1", result.RegisteredDevices)
	}
	if result.Delivered != 0 {
		t.Fatalf("delivered = %d, want 0", result.Delivered)
	}
	if remaining := eventStore.DevicesForTopic("codex"); len(remaining) != 0 {
		t.Fatalf("remaining devices = %d, want 0", len(remaining))
	}
}

func newTestStore(t *testing.T) *store.Store {
	t.Helper()

	eventStore, err := store.New(t.TempDir()+"/store.json", log.New(io.Discard, "", 0))
	if err != nil {
		t.Fatalf("new store: %v", err)
	}
	return eventStore
}

type stubAPNSClient struct {
	errorsByToken    map[string]error
	sentDeviceTokens []string
}

func (c *stubAPNSClient) Send(_ context.Context, deviceToken string, _ store.Event) error {
	c.sentDeviceTokens = append(c.sentDeviceTokens, deviceToken)
	if c.errorsByToken == nil {
		return nil
	}
	return c.errorsByToken[deviceToken]
}
