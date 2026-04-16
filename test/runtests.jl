using TestItemRunner

# Default run skips integration tests (they build full Piccolo problems and
# are slow without Piccolissimo). Run them explicitly with:
#   run_tests("."; filter=ti -> :integration in ti.tags)
@run_package_tests filter=ti -> !(:integration in ti.tags)
