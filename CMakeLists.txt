cmake_minimum_required(VERSION 3.12)
project(udhcp-sql VERSION 0.9.9 LANGUAGES C)

# Set C standard
set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Build options
option(ENABLE_MYSQL "Enable MySQL support" ON)
option(ENABLE_DEBUG "Enable debug output" ON)
option(ENABLE_SYSLOG "Use syslog for logging" OFF)
option(COMBINED_BINARY "Build combined client/server binary" ON)
option(BUILD_TESTS "Build test suite" OFF)

# Find required packages
find_package(PkgConfig REQUIRED)

if(ENABLE_MYSQL)
    pkg_check_modules(MYSQL REQUIRED mysqlclient)
endif()

# Compiler flags
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wstrict-prototypes -D_GNU_SOURCE")

if(ENABLE_DEBUG)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -g -DUDHCP_DEBUG")
endif()

if(ENABLE_SYSLOG)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DUDHCP_SYSLOG")
endif()

if(COMBINED_BINARY)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DCOMBINED_BINARY")
endif()

if(ENABLE_MYSQL)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DDHCPsql")
endif()

# Include directories
include_directories(include)
if(ENABLE_MYSQL)
    include_directories(${MYSQL_INCLUDE_DIRS})
endif()

# Source files organized by component
set(COMMON_SOURCES
    src/common/common.c
    src/common/options.c
    src/common/packet.c
    src/common/pidfile.c
    src/common/signalpipe.c
    src/common/socket.c
)

set(SERVER_SOURCES
    src/server/dhcpd.c
    src/server/arpping.c
    src/server/files.c
    src/server/leases.c
    src/server/static_leases.c
)

set(CLIENT_SOURCES
    src/client/dhcpc.c
    src/client/clientpacket.c
    src/client/clientsocket.c
    src/client/script.c
)

# MySQL-specific sources
if(ENABLE_MYSQL)
    list(APPEND SERVER_SOURCES
        src/server/serverpacket_mysql.c
        src/server/static_leases_mysql.c
    )
else()
    list(APPEND SERVER_SOURCES src/server/serverpacket.c)
endif()

# Main executable
if(COMBINED_BINARY)
    add_executable(udhcpd
        ${COMMON_SOURCES}
        ${SERVER_SOURCES}
        ${CLIENT_SOURCES}
        src/utils/frontend.c
    )
    
    if(ENABLE_MYSQL)
        target_link_libraries(udhcpd ${MYSQL_LIBRARIES})
    endif()
    
    # Create symlink for client
    add_custom_command(TARGET udhcpd POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E create_symlink udhcpd udhcpc
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
        COMMENT "Creating udhcpc symlink")
        
else()
    # Separate server binary
    add_executable(udhcpd
        ${COMMON_SOURCES}
        ${SERVER_SOURCES}
    )
    
    # Separate client binary
    add_executable(udhcpc
        ${COMMON_SOURCES}
        ${CLIENT_SOURCES}
    )
    
    if(ENABLE_MYSQL)
        target_link_libraries(udhcpd ${MYSQL_LIBRARIES})
    endif()
endif()

# Lease dump utility
add_executable(dumpleases src/utils/dumpleases.c)
if(ENABLE_MYSQL)
    target_link_libraries(dumpleases ${MYSQL_LIBRARIES})
endif()

# Installation
include(GNUInstallDirs)

if(COMBINED_BINARY)
    install(TARGETS udhcpd DESTINATION ${CMAKE_INSTALL_SBINDIR})
    install(CODE "execute_process(COMMAND ${CMAKE_COMMAND} -E create_symlink udhcpd udhcpc WORKING_DIRECTORY \${CMAKE_INSTALL_PREFIX}/${CMAKE_INSTALL_SBINDIR})")
else()
    install(TARGETS udhcpd udhcpc DESTINATION ${CMAKE_INSTALL_SBINDIR})
endif()

install(TARGETS dumpleases DESTINATION ${CMAKE_INSTALL_BINDIR})

# Install configuration files
install(DIRECTORY config/ DESTINATION ${CMAKE_INSTALL_DATADIR}/udhcp
        PATTERN "CVS" EXCLUDE
        PATTERN "*.script" PERMISSIONS OWNER_READ OWNER_WRITE OWNER_EXECUTE GROUP_READ GROUP_EXECUTE WORLD_READ WORLD_EXECUTE)

# Install man pages
install(FILES docs/man/dumpleases.1 DESTINATION ${CMAKE_INSTALL_MANDIR}/man1)
install(FILES docs/man/udhcpd.conf.5 DESTINATION ${CMAKE_INSTALL_MANDIR}/man5)
install(FILES docs/man/udhcpc.8 docs/man/udhcpd.8 DESTINATION ${CMAKE_INSTALL_MANDIR}/man8)

# Testing
if(BUILD_TESTS)
    enable_testing()
    add_subdirectory(tests)
    
    # Basic functionality test
    add_test(NAME udhcpd_version
             COMMAND udhcpd --version
             WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
endif()

# Package configuration
set(CPACK_PACKAGE_NAME "udhcp-sql")
set(CPACK_PACKAGE_VERSION ${PROJECT_VERSION})
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Lightweight DHCP server with MySQL support")
set(CPACK_PACKAGE_VENDOR "uDHCP Project")
set(CPACK_PACKAGE_CONTACT "maintainer@example.com")

# DEB package specific
set(CPACK_DEBIAN_PACKAGE_DEPENDS "libc6, libmysqlclient21")
set(CPACK_DEBIAN_PACKAGE_SECTION "net")

# RPM package specific
set(CPACK_RPM_PACKAGE_GROUP "System Environment/Daemons")
set(CPACK_RPM_PACKAGE_REQUIRES "glibc, mysql-libs")

include(CPack)
