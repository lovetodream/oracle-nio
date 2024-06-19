# PL/SQL Stored Procedures

You can call PL/SQL stored procedures, functions and anonymous blocks from OracleNIO using ``OracleConnection/execute(_:options:logger:file:line:)``.

## Overview

Let's consider the following definition of a stored procedure in your database.

```
create or replace procedure myproc (
    a_Value1                            number,
    a_Value2                            out number
) as
begin
    a_Value2 := a_Value1 * 2;
end;
```

You can use the following Swift code to call the procedure.

```swift
let outBind = OracleRef(OracleNumber(0))
try await connection.execute("""
begin 
    myproc(\(OracleNumber(123)), \(outBind));
end;
""")
let value = outBind.decode(of: Int.self)
print(value) // 246
```

> Note: ``OracleNumber`` is used to encode Oracle's `NUMBER` datatype 
from Swift to the Oracle wire format. 
