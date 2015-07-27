Linguist
========
Web-based **Task Translation Service** for [IOI competitions](http://www.ioinformatics.org/).
This project has been proven at [IOI2014 in Taiwan](http://www.ioi2014.org/).

Disclaimer
----------
* A few open-source projects/resources are included within this repository; all of the copyrights of such projects/resources belong to their respective owners.
* The service quality is not guaranteed.

Todo/Roadmap
------------
* Clean up this repository
* Re-write the live preview to support synchronous scrolling.
* Check the compatibility with Google Chrome
* Support Docker for depolyment

Deployment Steps
----------------
1. **Ubuntu Desktop 14.04+** is highly recommended
2. Internet access is a must during deployment
3. Check and Run `deploy.sh` to prepare the environment
4. Launch `redis-server`
5. Launch app server `shotgun -o 0.0.0.0 -p 8080`
6. Check `users.json` and `tasks.json` in `DbInit/` to prepare initial data
7. Change working directory to `DbInit/` and Run `ruby dbinit.rb`
8. Visit `http://127.0.0.1:8080`

Contribution Welcome
--------------------
* Submit pull requests
* Push commits directly
* Report issues

License
-------
[The MIT License (MIT)](http://opensource.org/licenses/mit-license.php)

Copyright (c) 2014 Shao-Chung Chen <dannvix@gmail.com>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
