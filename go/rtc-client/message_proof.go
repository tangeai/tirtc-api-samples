package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"sync"
	"time"
)

const streamFixturePrefix = "tirtc-stream-v1\x00"

type commandProof struct {
	ID       uint32 `json:"id"`
	BytesHex string `json:"bytes_hex"`
}
type streamProof struct {
	ID        uint8  `json:"id"`
	Timestamp uint32 `json:"timestamp_ms"`
	BytesHex  string `json:"bytes_hex"`
}
type messageProof struct {
	mu        sync.Mutex
	fixture   bool
	nonce     []byte
	streamIDs []uint8
	commands  []commandProof
	streams   []streamProof
	failure   error
	changed   chan struct{}
}

func newMessageProof(ids []uint8, fixture bool) (*messageProof, error) {
	nonce := make([]byte, 16)
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	if len(ids) == 0 {
		ids = []uint8{0}
	}
	return &messageProof{fixture: fixture, nonce: nonce, streamIDs: ids, changed: make(chan struct{}, 4)}, nil
}
func (p *messageProof) commandInput(index int) (uint32, []byte) {
	id := uint32(0x2001)
	if index == 1 {
		id = 0xffffffff
	}
	payload := append(append([]byte{}, p.nonce...), byte(index), 0, 255, 128)
	return id, payload
}
func (p *messageProof) streamInput(index int) (uint8, time.Duration, []byte) {
	stamp := uint32(0)
	if index == 1 {
		stamp = 0xffffffff
	}
	payload := append([]byte(streamFixturePrefix+"\x00"), p.nonce...)
	payload = binary.BigEndian.AppendUint32(payload, uint32(index))
	payload = append(payload, 0, 255, 128)
	return p.streamIDs[index%len(p.streamIDs)], time.Duration(stamp) * time.Millisecond, payload
}
func (p *messageProof) command(id uint32, data []byte) {
	p.mu.Lock()
	defer p.mu.Unlock()
	index := len(p.commands)
	if index >= 2 {
		p.failure = errors.New("duplicate command response")
	} else {
		expected, payload := p.commandInput(index)
		if id != expected || !bytes.Equal(data, payload) {
			p.failure = errors.New("command ID/order/binary mismatch")
		}
	}
	p.commands = append(p.commands, commandProof{id, hex.EncodeToString(data)})
	select {
	case p.changed <- struct{}{}:
	default:
	}
}
func (p *messageProof) stream(id uint8, stamp time.Duration, data []byte) {
	if !p.fixture || !bytes.HasPrefix(data, []byte(streamFixturePrefix)) {
		return
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	index := len(p.streams)
	if index >= 2 {
		p.failure = errors.New("duplicate stream response")
	} else {
		expected, timestamp, payload := p.streamInput(index)
		payload[len(streamFixturePrefix)] = 1
		if id != expected || stamp != timestamp || !bytes.Equal(data, payload) {
			p.failure = errors.New("stream ID/timestamp/order/binary mismatch")
		}
	}
	p.streams = append(p.streams, streamProof{id, uint32(stamp / time.Millisecond), hex.EncodeToString(data)})
	select {
	case p.changed <- struct{}{}:
	default:
	}
}
func (p *messageProof) wait(ctx context.Context) error {
	for {
		p.mu.Lock()
		failure := p.failure
		done := len(p.commands) == 2 && (!p.fixture || len(p.streams) == 2)
		p.mu.Unlock()
		if failure != nil {
			return failure
		}
		if done {
			return nil
		}
		select {
		case <-ctx.Done():
			return errors.New("message acceptance did not become exact remote delivery")
		case <-p.changed:
		}
	}
}
func (p *messageProof) save(path string) error {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if err := p.wait(ctx); err != nil {
		return err
	}
	p.mu.Lock()
	defer p.mu.Unlock()
	mode := "device"
	if p.fixture {
		mode = "stream-echo"
	}
	data, err := json.Marshal(map[string]any{"status": "passed", "peer_mode": mode, "commands": p.commands, "streams": p.streams})
	if err != nil {
		return err
	}
	return os.WriteFile(path, append(data, '\n'), 0600)
}
