# OracleNIO

This driver is in a very early stage of development.

## Goals

A Oracle Driver/Client which is 100% written in Swift using SwiftNIO, communicating directly to Oracle DBs, without using Oracle Client Libraries.

Communication with Oracle DBs has no public documentation, because of that [python-oracledb](https://github.com/oracle/python-oracledb), especially the thin driver, is used as the main reference. 

> Contributions in any way are appreciated. 

## Developing and Tinkering

To try things out you can run the embedded executable. 
As of now only username and password authentication are supported.

The following environment values are available to be set:

 - `ORA_IP_ADDRESS`: IP Address of the Oracle Database
 - `ORA_PORT`: Port of the Oracle Database (default: 1521)
 - `ORA_SERVICE_NAME`: Service Name of the Oracle Database (default: XEPDB1)
 - `ORA_USERNAME`: Username (default: my_user)
 - `ORA_PASSWORD`: Password (default: my_passwor)
