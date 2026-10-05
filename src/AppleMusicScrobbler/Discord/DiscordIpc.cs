using System;
using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace AppleMusicScrobbler.Discord
{
    /// <summary>
    /// Talks to the Discord desktop app over its local named pipe (\\.\pipe\discord-ipc-N),
    /// the same "Rich Presence" protocol the official SDKs use. Frames are
    /// [int32 opcode][int32 length][UTF-8 JSON], little-endian.
    /// </summary>
    sealed class DiscordIpc : IDisposable
    {
        enum Opcode { Handshake = 0, Frame = 1, Close = 2, Ping = 3, Pong = 4 }

        readonly SemaphoreSlim _writeLock = new SemaphoreSlim(1, 1);
        NamedPipeClientStream _pipe;
        volatile bool _connected;

        public bool IsConnected => _connected;

        /// <summary>Last error Discord reported for a command (e.g. an invalid activity), for the log.</summary>
        public event Action<string> Error;

        public async Task ConnectAsync(string clientId)
        {
            for (int i = 0; i < 10 && _pipe == null; i++)
            {
                var pipe = new NamedPipeClientStream(".", "discord-ipc-" + i, PipeDirection.InOut, PipeOptions.Asynchronous);
                try
                {
                    await Task.Run(() => pipe.Connect(250)).ConfigureAwait(false);
                    _pipe = pipe;
                }
                catch
                {
                    pipe.Dispose();
                }
            }
            if (_pipe == null) throw new IOException("Discord isn't running");

            await WriteAsync(Opcode.Handshake, "{\"v\":1,\"client_id\":" + Json.Str(clientId) + "}").ConfigureAwait(false);
            var (op, payload) = await ReadFrameAsync().ConfigureAwait(false);
            if (op != Opcode.Frame || !payload.Contains("\"READY\""))
                throw new IOException("Discord refused the connection: " + payload);

            _connected = true;
            _ = ReadLoopAsync();
        }

        /// <summary>Shows an activity (a JSON object) or clears it (null).</summary>
        public Task SetActivityAsync(string activityJson)
        {
            string command = "{\"cmd\":\"SET_ACTIVITY\",\"args\":{\"pid\":" + Process.GetCurrentProcess().Id +
                             ",\"activity\":" + (activityJson ?? "null") + "},\"nonce\":\"" + Guid.NewGuid() + "\"}";
            return WriteAsync(Opcode.Frame, command);
        }

        async Task ReadLoopAsync()
        {
            try
            {
                while (_connected)
                {
                    var (op, payload) = await ReadFrameAsync().ConfigureAwait(false);
                    switch (op)
                    {
                        case Opcode.Ping:
                            await WriteAsync(Opcode.Pong, payload).ConfigureAwait(false);
                            break;
                        case Opcode.Close:
                            throw new IOException("Discord closed the connection: " + payload);
                        case Opcode.Frame:
                            if (payload.Contains("\"evt\":\"ERROR\"")) Error?.Invoke(payload);
                            break;
                    }
                }
            }
            catch
            {
                // Discord quit or the pipe broke; the owner reconnects later.
            }
            finally
            {
                _connected = false;
            }
        }

        async Task WriteAsync(Opcode op, string json)
        {
            byte[] body = Encoding.UTF8.GetBytes(json);
            byte[] frame = new byte[8 + body.Length];
            BitConverter.GetBytes((int)op).CopyTo(frame, 0);
            BitConverter.GetBytes(body.Length).CopyTo(frame, 4);
            body.CopyTo(frame, 8);

            await _writeLock.WaitAsync().ConfigureAwait(false);
            try
            {
                await _pipe.WriteAsync(frame, 0, frame.Length).ConfigureAwait(false);
                await _pipe.FlushAsync().ConfigureAwait(false);
            }
            catch
            {
                _connected = false;
                throw;
            }
            finally
            {
                _writeLock.Release();
            }
        }

        async Task<(Opcode, string)> ReadFrameAsync()
        {
            byte[] header = await ReadExactlyAsync(8).ConfigureAwait(false);
            int op = BitConverter.ToInt32(header, 0);
            int length = BitConverter.ToInt32(header, 4);
            if (length < 0 || length > 1_000_000) throw new IOException("Unexpected data from Discord");
            byte[] body = await ReadExactlyAsync(length).ConfigureAwait(false);
            return ((Opcode)op, Encoding.UTF8.GetString(body));
        }

        async Task<byte[]> ReadExactlyAsync(int count)
        {
            byte[] buffer = new byte[count];
            int read = 0;
            while (read < count)
            {
                int n = await _pipe.ReadAsync(buffer, read, count - read).ConfigureAwait(false);
                if (n == 0) throw new EndOfStreamException("Discord closed the connection");
                read += n;
            }
            return buffer;
        }

        public void Dispose()
        {
            _connected = false;
            try { _pipe?.Dispose(); } catch { }
            _pipe = null;
        }
    }
}
