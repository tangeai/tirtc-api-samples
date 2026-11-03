package main

import (
	"context"
	"testing"
	"time"
)

func TestMessageProofRequiresExactDeliveredBinary(t *testing.T) {
	p, _ := newMessageProof([]uint8{11, 12}, true)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if p.wait(ctx) == nil {
		t.Fatal("acceptance without delivery passed")
	}
	for i := 0; i < 2; i++ {
		id, data := p.commandInput(i)
		p.command(id, data)
	}
	if p.wait(ctx) == nil {
		t.Fatal("missing stream delivery passed")
	}
	for i := 0; i < 2; i++ {
		id, stamp, data := p.streamInput(i)
		data[len(streamFixturePrefix)] = 1
		p.stream(id, stamp, data)
	}
	if err := p.wait(ctx); err != nil {
		t.Fatal(err)
	}
	id, data := p.commandInput(0)
	p.command(id, data)
	if p.wait(ctx) == nil {
		t.Fatal("duplicate response passed")
	}
}
func TestMessageProofRejectsWrongIDTimestampBytesAndOrder(t *testing.T) {
	for _, mutation := range []string{"id", "time", "bytes", "order"} {
		t.Run(mutation, func(t *testing.T) {
			p, _ := newMessageProof([]uint8{11, 12}, true)
			index := 0
			if mutation == "order" {
				index = 1
			}
			id, stamp, data := p.streamInput(index)
			data[len(streamFixturePrefix)] = 1
			switch mutation {
			case "id":
				id++
			case "time":
				stamp += time.Millisecond
			case "bytes":
				data = append(data, 0)
			}
			p.stream(id, stamp, data)
			ctx, cancel := context.WithCancel(context.Background())
			cancel()
			if p.wait(ctx) == nil {
				t.Fatal("invalid response passed")
			}
		})
	}
}
