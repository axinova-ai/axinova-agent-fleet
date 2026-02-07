package main

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
)

// Example MCP client that communicates with axinova-mcp-server via stdio

type MCPRequest struct {
	JSONRPC string                 `json:"jsonrpc"`
	Method  string                 `json:"method"`
	Params  map[string]interface{} `json:"params,omitempty"`
	ID      int                    `json:"id"`
}

type MCPResponse struct {
	JSONRPC string                 `json:"jsonrpc"`
	Result  map[string]interface{} `json:"result,omitempty"`
	Error   *MCPError              `json:"error,omitempty"`
	ID      int                    `json:"id"`
}

type MCPError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func main() {
	ctx := context.Background()

	// Start MCP server process
	serverPath := "/Users/weixia/axinova/axinova-mcp-server-go/bin/axinova-mcp-server"
	cmd := exec.CommandContext(ctx, serverPath)

	// Set up environment (read from actual config)
	cmd.Env = append(os.Environ(),
		"ENV=prod",
		"APP_VIKUNJA__URL=https://vikunja.axinova-internal.xyz",
		"APP_VIKUNJA__TOKEN="+os.Getenv("VIKUNJA_TOKEN"),
		// Add other MCP server env vars...
	)

	// Create pipes for stdin/stdout
	stdin, err := cmd.StdinPipe()
	if err != nil {
		panic(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		panic(err)
	}

	// Start server
	if err := cmd.Start(); err != nil {
		panic(err)
	}
	defer cmd.Wait()

	// Example: List Vikunja projects
	req := MCPRequest{
		JSONRPC: "2.0",
		Method:  "tools/call",
		Params: map[string]interface{}{
			"name":      "vikunja_list_projects",
			"arguments": map[string]interface{}{},
		},
		ID: 1,
	}

	// Send request
	if err := json.NewEncoder(stdin).Encode(req); err != nil {
		panic(err)
	}

	// Read response
	scanner := bufio.NewScanner(stdout)
	if scanner.Scan() {
		var resp MCPResponse
		if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
			panic(err)
		}

		if resp.Error != nil {
			fmt.Printf("Error: %s\n", resp.Error.Message)
		} else {
			fmt.Printf("Result: %+v\n", resp.Result)
		}
	}

	// Example: Create Vikunja task
	createTaskReq := MCPRequest{
		JSONRPC: "2.0",
		Method:  "tools/call",
		Params: map[string]interface{}{
			"name": "vikunja_create_task",
			"arguments": map[string]interface{}{
				"project_id":  1,
				"title":       "Test task from agent",
				"description": "<p>Created via MCP client</p>",
				"priority":    3,
			},
		},
		ID: 2,
	}

	if err := json.NewEncoder(stdin).Encode(createTaskReq); err != nil {
		panic(err)
	}

	if scanner.Scan() {
		var resp MCPResponse
		if err := json.Unmarshal(scanner.Bytes(), &resp); err != nil {
			panic(err)
		}

		if resp.Error != nil {
			fmt.Printf("Error: %s\n", resp.Error.Message)
		} else {
			fmt.Printf("Created task: %+v\n", resp.Result)
		}
	}

	// Close stdin to signal end of communication
	stdin.Close()

	// Wait for remaining output
	io.Copy(os.Stdout, stdout)
}
