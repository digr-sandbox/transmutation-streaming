package context

import "fmt"

type ContextManager struct {
    SessionID string
}

func (cm *ContextManager) Authenticate(token string) (bool, error) {
    fmt.Printf("Go Auth: %s\n", cm.SessionID)
    if token == "" { return false, fmt.Errorf("invalid") }
    return true, nil
}