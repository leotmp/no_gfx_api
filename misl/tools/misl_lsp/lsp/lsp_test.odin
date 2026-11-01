package lsp

import tests "core:testing"
import "core:fmt"
import "core:os"
import "core:io"
import "core:encoding/json"

@test
test_unmarshal :: proc(T: ^tests.T) {
    initialize_msg := #load("test_messages/initialize.json", []byte)
    request: Request_Message(Initialize_Params)
    err := json.unmarshal(initialize_msg, &request)
    tests.expectf(T, err == nil, "Failed to unmarshal: %v", err)
    fmt.printf("%#v\n", request)
}

@test
test_send :: proc(T: ^tests.T) {
    writer := os.to_stream(os.stdout)
    msg: Response_Message
    msg.jsonrpc = "2.0.0"
    msg.id = 1
    msg.result = Initialize_Result {
        capabilities = Server_Capabilities {
            workspace_symbol_provider = true,
        },
    }
    ok := send(msg, writer)
    fmt.printf("\n") // Send prints to stdout and it doesn't newline
    tests.expect(T, ok, "Failed to send message")
}