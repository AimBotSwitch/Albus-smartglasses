# This work is licensed under the MIT license.
# Copyright (c) 2013-2023 OpenMV LLC. All rights reserved.
# https://github.com/openmv/openmv/blob/master/LICENSE
#
# MJPEG Streaming
#
# This example shows off how to do MJPEG streaming to a FIREFOX webrowser
# Chrome, Firefox and MJpegViewer App on Android have been tested.
# Connect to the IP address/port printed out from ifconfig to view the stream.

import sensor
import time
import network
import socket
import ujson

DISCOVERY_PORT = 19999
SSID = "xbeast"  # Network SSID
KEY = "1135d1135d"  # Network key
HOST = ""  # Use first available interface
PORT = 8081  # Arbitrary non-privileged port

# Init sensor
sensor.reset()
sensor.set_framesize(sensor.QVGA)
sensor.set_pixformat(sensor.RGB565)

# Init wlan module and connect to network
network.hostname("nicla-vision")
wlan = network.WLAN(network.STA_IF)
wlan.active(True)
wlan.ifconfig(("192.168.86.47", "255.255.255.0", "192.168.1.1", "192.168.1.1"))
wlan.connect(SSID, KEY)

while not wlan.isconnected():
    print('Trying to connect to "{:s}"...'.format(SSID))
    time.sleep_ms(1000)

# We should have a valid IP now via DHCP
print("WiFi Connected ", wlan.ifconfig())

ip = wlan.ifconfig()[0]
bc = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
bc.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
beacon = ujson.dumps({
  "svc":"mjpeg","name":"NiclaVision","ip":ip,
  "port":PORT,"path":"/","ver":1
}).encode()
last = time.ticks_ms()
for _ in range(10):
    print("try sending discovery beaco, ts: ", last)
    if time.ticks_diff(time.ticks_ms(), last) > 2000:
        try:
            bc.sendto(beacon, ("255.255.255.255", DISCOVERY_PORT))
            print("beacon sent")
        except OSError:
            pass
        last = time.ticks_ms()
    time.sleep_ms(2000)

# Create server socket
s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, True)

# Bind and listen
s.bind([HOST, PORT])
s.listen(5)

# Set server socket to blocking
s.setblocking(True)


def start_streaming(s):
    print("Waiting for connections..")
    client, addr = s.accept()
    # set client socket timeout to 5s
    client.settimeout(5.0)
    print("Connected to " + addr[0] + ":" + str(addr[1]))

    # Read request from client
    data = client.recv(1024)
    # Should parse client request here

    # Send multipart header
    client.sendall(
        "HTTP/1.1 200 OK\r\n"
        "Server: OpenMV\r\n"
        "Content-Type: multipart/x-mixed-replace;boundary=openmv\r\n"
        "Cache-Control: no-cache\r\n"
        "Pragma: no-cache\r\n\r\n"
    )

    # FPS clock
    clock = time.clock()

    # Start streaming images
    # NOTE: Disable IDE preview to increase streaming FPS.
    while True:
        clock.tick()  # Track elapsed milliseconds between snapshots().
        frame = sensor.snapshot()
        cframe = frame.to_jpeg(quality=35, copy=True)
        header = (
            "\r\n--openmv\r\n"
            "Content-Type: image/jpeg\r\n"
            "Content-Length:" + str(cframe.size()) + "\r\n\r\n"
        )
        client.sendall(header)
        client.sendall(cframe)
        print(clock.fps())

while True:
    try:
        start_streaming(s)
    except OSError as e:
        print("socket error: ", e)
        # sys.print_exception(e)
