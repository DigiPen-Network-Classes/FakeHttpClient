# Fake Http Client

This is some test-automation to be used with CS 260's Assignment 3:
the Http Proxy assignment. Originally all of this was written using .BAT
but increasingly, getting that to work is becoming an issue. In particular:
we want the invocations of the client program to be simultaneous, and that
is difficult to do with PowerShell and BAT files.

This is all still VERY experimental.


# Instructions

TODO write instructions

Example: run one url - the default is http://cs260.meancat.com/delay

```pwsh
C:\> ./assign3 runOne
```

Or target a url of your choice:
```pwsh
C:\> ./assign3 runOne -Url http://www.google.com/
```

To run vs. many urls and see if you are really non-blocking:
```pwsh
C:\> ./assign3 runAll
```

This will create a `results`  directory and write error and output to files.
On success, all of the "-Error.txt" files should be zero bytes. If there was an error 
from the FakeHttpClient, it will be printed there.

On success, there should be a number of "-Results.txt" files, with the HTML output
from the webserver (via your proxy assignment program).

You should see something like this, although your details will be different:
```html
Operation Started At: Sat Oct 26 16:54:48 2024

Connected At: Sat Oct 26 16:54:48 2024

Send Complete At Sat Oct 26 16:54:48 2024

HTTP/1.1 200 OK
Server: nginx/1.18.0
Date: Sat, 26 Oct 2024 23:54:49 GMT
Transfer-Encoding: chunked
Connection: close
X-Powered-By: Express

65
<html><head><title>DigiPen CS 260 Delayed Response Test</title></head><body><h2>Here we go!</h2>1<br>
```
... and then a bunch of html.

At the bottom of the file the connected and total times are printed in milliseconds.
```
Connected: 5144 ms
Total Elapsed: 5195 ms
```

Check these numbers at the bottom of each "results" file.
If the requests are running concurrently, then these numbers should be roughly same (but not exactly).

```
File 1:
Connected: 5144 ms
Total Elapsed: 5195 ms

File 2:
Connected: 5093 ms
Total Elapsed: 5174 ms
```

If they are NOT running concurrently, then you'd see either number start to get much larger with
each result file.


