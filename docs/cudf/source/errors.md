# cuDF Error Handling Documentation (draft)

## Scope

This document serves to guide the use of error types when dealing with different exceptions encountered within cuDF domain. As of the draft version, it also serves as a reference for supporting libraries (like libcudf) to boost awareness of common error types encountered and to standardize their error interface. Note that this document will not serve as a complete list of error types thrown by cuDF.

## Overview

On a high level, exceptions consist of exception type and exception payload. Each can be standardized by the API. cuDF only standardizes exception type and uses the payload to convey debugging information for users. (Subject to discussion: is it sufficient to only use builtin error types but not the payload to signal all errors?)

cuDF follows error conventions used by Pandas. Following [Pandas Wiki](https://github.com/pandas-dev/pandas/wiki/Choosing-Exceptions-to-Raise), cuDF uses python [builtin error types](https://docs.python.org/3.9/library/exceptions.html) whenever possible. Common builtin errors used in cuDF and their semantics are listed below.

| builtin error type | semantic | example use case |
| ------------------ | -------- | ---------------- |
|     TypeError      | Operation is applied to unsupported objects. For objects that is not **yet** supported, use `NotImplementedError` | [binary operation on two unsupported column types](https://github.com/rapidsai/cudf/blob/7d49f75df9681dbe1653029e7d508355884a6d86/python/cudf/cudf/core/column/numerical.py#L110) |
|     ValueError     | The value of the object does not satisfy operation requirement. Usually raising this error requires data introspection. In cases where the object only accept from a finite set of values (such as enum or string set), also use `ValueError`. | [The dataframe to describe is empty](https://github.com/rapidsai/cudf/blob/7d49f75df9681dbe1653029e7d508355884a6d86/python/cudf/cudf/core/dataframe.py#L5366) |
|     IndexError     | Array access out of range | [Retrieving rows from a column specified by an out of bound index](https://github.com/rapidsai/cudf/blob/7d49f75df9681dbe1653029e7d508355884a6d86/python/cudf/cudf/core/column/column.py#L849-L851) |
|     KeyError       | Mapping access with invalid key | [Retrieving rows from column specified by an invalid key](https://github.com/rapidsai/cudf/blob/7d49f75df9681dbe1653029e7d508355884a6d86/python/cudf/cudf/core/indexing.py#L177) |
| NotImplementedError| Operation of object is planned, but not yet supported | (none) |

|  FileNotFoundError | File could not be found at user specified location | https://github.com/rapidsai/cudf/blob/4893259b2fd6cf1f2079eff68249290708519892/python/cudf/cudf/_lib/csv.pyx#L369 |
|   OverflowError    | Numerical overflows | (Usually surfacing from supporting libraries?)  |
|     IOError        | (TBA by cuIO) | (TBA) |
|     OSError        | Operating system failure | (TBA) |

Custom error types, should not be used whenever possible.

Errors raised by the API are considered part of the API and should be documented in the docstring. For a specific invalid input, changing the raised exception is considered a breaking change.

## Handling Exceptions Thrown by Supporting Libraries

cuDF depends on external libraries to function. While cuDF does extensive tests on inputs to make sure data passed to lower level is legal, supporting libraries may also perform their own data checks. Very often such checks are redundant. Double-checking adds unecessary latency to cuDF API calls and is thus unwanted. To allow reusing error checks from supporting libraries, the following section explains how cuDF proposes to map errors from supporting libraries to cuDF errors.

Note that this does not mean cuDF will skip checking errors. As supporting libraries have different performance constraints to cuDF, cuDF should perform checks when necessary. An example is that libcudf [does not introspect data](https://github.com/rapidsai/cudf/issues/5505), but cuDF should.

### Python Libraries

If Python libraries raise a builtin error type, cuDF will surface that error.

If python libraries throws a custom error type, cuDF will attempt to reinterpret it into builtin error type.

### C++ Libraries

cuDF interfaces with C++ libraries through Cython. By default, cuDF captures all exceptions thrown by C++ libraries. Cython maps these exceptions into Python errors as outlined by [this document](http://docs.cython.org/en/latest/src/userguide/wrapping_CPlusPlus.html#exceptions).

In cases where the meaning of a C++ exception can be unambiguously determined, cuDF will skip any checks in Python and directly surface such exceptions via Cython's C++->Python exception mapping. However, in some cases the exceptions may be ambiguous. For example, a C++ function may raise two instances of `std::invalid_argument` error, each signaling different kinds of invalid argument combination. In that case, cuDF will check the invalid combinations and re-raise with proper user message.

In cases when the contents of [`what()`](https://www.cplusplus.com/reference/exception/exception/what/) is standardized by the supporting library, cuDF will utilize it to disambiguate.
