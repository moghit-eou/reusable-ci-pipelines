// Small Docker client, used as a scan target for the SAST and SCA pipelines.
package main

import (
	"context"
	"log"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/client"
)

func main() {
	ctx := context.Background()

	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		log.Fatalf("failed to create docker client: %v", err)
	}
	defer cli.Close()

	containers, err := cli.ContainerList(ctx, container.ListOptions{All: true})
	if err != nil {
		log.Fatalf("failed to list containers: %v", err)
	}

	for _, c := range containers {
		log.Printf("%.12s  %-10s  %s", c.ID, c.State, c.Image)
	}
}
