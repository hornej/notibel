package apns

import (
	"strings"
	"testing"
	"unicode/utf8"
)

func TestAlertBodyKeepsShortMessages(t *testing.T) {
	message := "Short response body."

	if got := alertBody(message); got != message {
		t.Fatalf("alertBody() = %q, want %q", got, message)
	}
}

func TestAlertBodyTruncatesLongMessages(t *testing.T) {
	message := strings.Repeat("abcd", 100)

	got := alertBody(message)

	if got == message {
		t.Fatal("alertBody() did not truncate a long message")
	}
	if !strings.HasSuffix(got, "...") {
		t.Fatalf("alertBody() = %q, want ellipsis suffix", got)
	}
	if utf8.RuneCountInString(got) > 243 {
		t.Fatalf("alertBody() length = %d, want <= 243 runes", utf8.RuneCountInString(got))
	}
}

func TestAlertBodyFallsBackForBlankMessages(t *testing.T) {
	got := alertBody("   ")

	if got == "" {
		t.Fatal("alertBody() returned an empty string for a blank message")
	}
}
