# Regression tests

Build and run on Linux with CMake, a C compiler, pkg-config and the MySQL client
headers/library installed:

```sh
cmake -S . -B /tmp/dhcpsql-tests -DBUILD_TESTS=ON -DENABLE_MYSQL=ON
cmake --build /tmp/dhcpsql-tests -j2
ctest --test-dir /tmp/dhcpsql-tests --output-on-failure
```

Also build with `-DENABLE_MYSQL=OFF` to check the file-backed lease implementation.
For memory checks, add `-DCMAKE_C_FLAGS='-fsanitize=address,undefined -fno-omit-frame-pointer'`.

- `test_options`: truncated options, fixed-width values, option overload, all
  option-field length boundaries, SQL numeric values and immutable SQL rows.
- `test_mysql`: a MySQL API double with real DHCP option, reply and lease code;
  checks address byte order, database errors/recovery, reservation enforcement,
  one lease-time option per reply, class overrides and packet/accounting agreement.
- `test_runner`: counters and continued execution after a failed shell test.

The MySQL double does not validate SQL against a running MySQL server or send
network packets. These are regression tests, not a replacement for a live DHCP
integration test.
