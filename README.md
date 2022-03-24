# Install script for Site Wide Analysis Tool Agent
[![Functional Tests](https://github.com/magento-swat/install-agent-helpers/actions/workflows/functional-tests.yml/badge.svg?branch=main)](https://github.com/magento-swat/install-agent-helpers/actions/workflows/functional-tests.yml)
[![Lint Code Base](https://github.com/magento-swat/install-agent-helpers/actions/workflows/super-linter.yml/badge.svg)](https://github.com/magento-swat/install-agent-helpers/actions/workflows/super-linter.yml)

The Site-Wide Analysis Tool provides 24/7 real-time performance monitoring, reports, and recommendations to ensure the security and operability of Adobe Commerce on cloud infrastructure installations. It also provides detailed information about available and installed patches, third-party extensions, and your Adobe Commerce installation.

For on-premises installation of Adobe Commerce, you must install an agent on your infrastructure to use the tool. You do not need to install the agent on Adobe Commerce on cloud infrastructure projects.

Agent Install Guide: https://devdocs.magento.com/tools/site-wide-analysis.html

## How to run tests
Functional tests are created with by `expect`.
Run the following command to build docker image and run tests

```
bash tests/functional-tests.sh
```

## How to create a new test
To create a new test you can use `autoexpect` and generate a test.

1. Build a docker image 
  ```
  docker build -f tests/Dockerfile -t installer-functional-test .
  ```
2. Generate a test 

```
docker run -v "$(pwd)":/app --rm -it installer-functional-test autoexpect /app/install.sh
```

3. Copy test into the tests directory and update tests/functional-tests.sh file
