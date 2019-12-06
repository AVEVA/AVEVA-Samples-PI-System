if (!require("pacman")) install.packages("pacman", repos = "https://cran.r-project.org", quiet = TRUE)
require("pacman", quietly = TRUE)
p_load("testthat", "xml2")

#Path to the test folder
#For the automated build, this must be ".", if errors occur, try specifying the full path (i.e. from C:\)
path <- "."

#Suppress UI
Sys.setenv("TESTING" = TRUE)

options(testthat.output_file = paste(path, "\\output.xml", sep = ""))
test_results <- test_dir(path, env = test_env(), reporter="junit")

Sys.unsetenv("TESTING")
