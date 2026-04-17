package httpapi

import (
	"bytes"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/hornej/notibel/internal/config"
	"github.com/hornej/notibel/internal/notifier"
	"github.com/hornej/notibel/internal/store"
)

func TestPublishStoresEvent(t *testing.T) {
	t.Parallel()

	handler, eventStore := newTestHandler(t)

	response := performJSONRequest(t, handler, http.MethodPost, "/v1/publish/codex", "publish-token", map[string]any{
		"message": "Finished the task.",
		"title":   "Codex",
	})

	if response.Code != http.StatusOK {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusOK)
	}

	events := eventStore.EventsForTopic("codex", 10)
	if len(events) != 1 {
		t.Fatalf("event count = %d, want 1", len(events))
	}
	if events[0].Message != "Finished the task." {
		t.Fatalf("stored message = %q, want %q", events[0].Message, "Finished the task.")
	}
}

func TestPublishRejectsUnknownFields(t *testing.T) {
	t.Parallel()

	handler, _ := newTestHandler(t)

	response := performJSONRequest(t, handler, http.MethodPost, "/v1/publish/codex", "publish-token", map[string]any{
		"message":    "Finished the task.",
		"unexpected": true,
	})

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
}

func TestPublishRejectsEmptyMessage(t *testing.T) {
	t.Parallel()

	handler, _ := newTestHandler(t)

	response := performJSONRequest(t, handler, http.MethodPost, "/v1/publish/codex", "publish-token", map[string]any{
		"title": "Codex",
	})

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
}

func TestPublishReturnsInternalErrorForStoreFailures(t *testing.T) {
	t.Parallel()

	tempDir := t.TempDir()
	logger := log.New(io.Discard, "", 0)
	eventStore, err := store.New(filepath.Join(tempDir, "store.json"), logger)
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	t.Cleanup(func() {
		_ = os.Chmod(tempDir, 0o700)
	})

	if err := os.Chmod(tempDir, 0o500); err != nil {
		t.Fatalf("chmod temp dir: %v", err)
	}

	cfg := config.Config{
		PublishToken: "publish-token",
		AppToken:     "app-token",
		EventLimit:   50,
	}

	handler := New(cfg, eventStore, notifier.New(eventStore, nil, logger, cfg.EventLimit), logger)
	response := performJSONRequest(t, handler, http.MethodPost, "/v1/publish/codex", "publish-token", map[string]any{
		"message": "Finished the task.",
		"title":   "Codex",
	})

	if response.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusInternalServerError)
	}
}

func TestTopicEventsRequireAppToken(t *testing.T) {
	t.Parallel()

	handler, _ := newTestHandler(t)

	request := httptest.NewRequest(http.MethodGet, "/v1/topics/codex/events", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusUnauthorized)
	}
}

func TestDeviceRegistrationRejectsInvalidTopics(t *testing.T) {
	t.Parallel()

	handler, _ := newTestHandler(t)

	response := performJSONRequest(t, handler, http.MethodPut, "/v1/devices/phone-1", "app-token", map[string]any{
		"deviceToken": "abc123",
		"topics":      []string{"codex", "bad/topic"},
		"name":        "My Phone",
	})

	if response.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, want %d", response.Code, http.StatusBadRequest)
	}
}

func newTestHandler(t *testing.T) (http.Handler, *store.Store) {
	t.Helper()

	logger := log.New(io.Discard, "", 0)
	eventStore, err := store.New(t.TempDir()+"/store.json", logger)
	if err != nil {
		t.Fatalf("new store: %v", err)
	}

	cfg := config.Config{
		PublishToken: "publish-token",
		AppToken:     "app-token",
		EventLimit:   50,
	}

	service := notifier.New(eventStore, nil, logger, cfg.EventLimit)
	return New(cfg, eventStore, service, logger), eventStore
}

func performJSONRequest(
	t *testing.T,
	handler http.Handler,
	method string,
	path string,
	token string,
	body any,
) *httptest.ResponseRecorder {
	t.Helper()

	payload, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}

	request := httptest.NewRequest(method, path, bytes.NewReader(payload))
	request.Header.Set("Content-Type", "application/json")
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}

	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	return response
}
