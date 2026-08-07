# NeoLogger

Swift rewrite of NSLogger: a client library that streams log Messages from an app to a Viewer over the network, wire-compatible with the original NSLogger desktop viewer.

## Language

**Message**:
An ordered list of typed Parts; the unit a client emits and a Viewer displays.
_Avoid_: log entry, event

**Part**:
One typed key/value pair inside a Message.
_Avoid_: field, attribute

**Payload**:
The body of a log Message: text, binary data, or a PNG image.
_Avoid_: content, body

**Frame**:
The NSLogger binary encoding of one Message on the wire.
_Avoid_: packet, chunk

**Transport**:
The seam Messages cross to leave the client. The adapter behind it owns the connection, wire encoding, the Handshake, and reconnection.
_Avoid_: connection, socket, sender

**Handshake**:
The client-info Message that precedes every other Message on each new connection.
_Avoid_: hello, preamble

**Viewer**:
The receiving program that decodes Frames and displays Messages (NSLogger.app or neo-logger-viewer).
_Avoid_: server, listener, receiver

**Domain**:
The logical grouping label on a Message (NSLogger's "tag" on the wire).
_Avoid_: tag, category

**Level**:
Numeric severity on a Message; lower is more severe.
_Avoid_: priority

**Mark**:
A labelled divider Message a Viewer renders between ordinary Messages.
