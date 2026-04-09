package store

import (
	"testing"
	"time"
)

func TestUpsertDeviceNormalizesTopics(t *testing.T) {
	t.Parallel()

	db, err := New(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	reg, err := db.UpsertDevice(DeviceRegistration{
		InstallationID: "phone-1",
		DeviceToken:    "abc123",
		Topics:         []string{"codex", "claude", "codex", " "},
	})
	if err != nil {
		t.Fatalf("upsert device: %v", err)
	}

	if got, want := len(reg.Topics), 2; got != want {
		t.Fatalf("topics length = %d, want %d", got, want)
	}
	if reg.Topics[0] != "claude" || reg.Topics[1] != "codex" {
		t.Fatalf("topics were not sorted and de-duplicated: %#v", reg.Topics)
	}
}

func TestAddEventPrunesOldEntries(t *testing.T) {
	t.Parallel()

	db, err := New(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	events := []Event{
		{ID: "1", Topic: "codex", Message: "one", CreatedAt: time.Unix(1, 0)},
		{ID: "2", Topic: "codex", Message: "two", CreatedAt: time.Unix(2, 0)},
		{ID: "3", Topic: "codex", Message: "three", CreatedAt: time.Unix(3, 0)},
	}

	for _, event := range events {
		if err := db.AddEvent(event, 2); err != nil {
			t.Fatalf("add event: %v", err)
		}
	}

	got := db.EventsForTopic("codex", 10)
	if len(got) != 2 {
		t.Fatalf("event count = %d, want 2", len(got))
	}
	if got[0].ID != "3" || got[1].ID != "2" {
		t.Fatalf("unexpected events after pruning: %#v", got)
	}
}

func TestEventByIDReturnsMatchingEvent(t *testing.T) {
	t.Parallel()

	db, err := New(t.TempDir() + "/store.json")
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	olderEvent := Event{ID: "1", Topic: "codex", Message: "older", CreatedAt: time.Unix(1, 0)}
	newerEvent := Event{ID: "2", Topic: "claude", Message: "newer", CreatedAt: time.Unix(2, 0)}

	if err := db.AddEvent(olderEvent, 10); err != nil {
		t.Fatalf("add older event: %v", err)
	}
	if err := db.AddEvent(newerEvent, 10); err != nil {
		t.Fatalf("add newer event: %v", err)
	}

	got, ok := db.EventByID("2")
	if !ok {
		t.Fatal("EventByID() did not find the event")
	}
	if got.ID != newerEvent.ID || got.Topic != newerEvent.Topic {
		t.Fatalf("EventByID() = %#v, want %#v", got, newerEvent)
	}
}
