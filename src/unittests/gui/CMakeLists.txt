# SPDX-FileCopyrightText: (C) 2025 Deskflow Developers
# SPDX-License-Identifier: MIT

add_subdirectory(config)
add_subdirectory(core)

if(APPLE)
  create_test(
    NAME ServerConfigDialogTests
    DEPENDS gui
    LIBS Qt::Widgets
    SOURCE ServerConfigDialogTests.cpp
    WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/src/lib/gui"
  )
  target_include_directories(ServerConfigDialogTests PRIVATE "${CMAKE_SOURCE_DIR}/src/lib/gui")
  set_tests_properties(ServerConfigDialogTests PROPERTIES ENVIRONMENT "QT_QPA_PLATFORM=offscreen")
endif()

create_test(
  NAME LoggerTests
  DEPENDS gui
  SOURCE LoggerTests.cpp
  WORKING_DIRECTORY "${CMAKE_BINARY_DIR}/src/lib/gui"
)
