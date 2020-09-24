def pytest_addoption(parser):
    parser.addoption("--use_buffer", action="store", default=False)


def pytest_generate_tests(metafunc):
    # This is called for every test. Only get/set command line arguments
    # if the argument is specified in the list of test "fixturenames".
    option_value = metafunc.config.option.use_buffer
    if "use_buffer" in metafunc.fixturenames and option_value is not None:
        metafunc.parametrize("use_buffer", [option_value])
