install.packages("RSelenium")
install.packages("tidyverse")

library(RSelenium)
library(rvest)
library(stringr)
library(tidyverse)
library(dplyr)

# Initiate Selenium browser
driver <- rsDriver(browser=c("chrome"), chromever = "87.0.4280.88")
remote_driver <- driver[["client"]]
remote_driver$open()

# Navigate to search page
remote_driver$navigate("http://sipp.pn-pangkalanbun.go.id/list_perkara/search")

# Locate search box
search_element <- remote_driver$findElement(using = 'id', value = 'search-box')

# Enter search term
search_element$sendKeysToElement(list("Kebakaran Hutan"))

# Locate search button
button_element <- remote_driver$findElement(using = 'id', value = 'search-btn1')

# Click search button
button_element$clickElement()

# Extract results table as html_table
scraped_table <- read_html(remote_driver$getPageSource()[[1]]) %>%
  html_nodes(xpath = '//*[@id="tablePerkaraAll"]') %>% html_table()

# Convert table to data frame
scraped_table_df <- as.data.frame(scraped_table)

# Rename table columns, adding underscores
colnames(scraped_table_df) <- c("No", "Nomor_Perkara", "Tanggal_Register", "Klasifikasi_Perkara", "Para_Pihak", "Status_Perkara", "Lama_Proses", "Link")

# Remove first row (which has column names in it)
scraped_table_df = scraped_table_df[-1,]

# Remove rownames
rownames(scraped_table_df) = NULL

# Delete "Link" column, which currently has just the hyperlink title in it ("detil")
scraped_table_df <- scraped_table_df[, -8]

# Convert "No" column to integer
scraped_table_df$No <- as.integer(scraped_table_df$No)

# Retrieve all URLs on the page residing in the "a" node. This returns all of the URLs on the whole page, which is too many. The last "n" of these links are the ones we want, where "n" is the number of rows in scraped_table_df
links <- read_html(remote_driver$getPageSource()[[1]]) %>%
  html_nodes("a") %>% html_attr("href")

# Turn "links" into a list
link_list <- as.list(links)

# Retain only the last "n" links, where "n" is the number of rows in scraped_table_df
link_list_2 <- tail(link_list, (nrow(scraped_table_df)))

# Append link_list_2 to scraped_table_df as "Link" column:
scraped_table_df$Link <- sapply(link_list_2, paste0)

# Read in previous version of csv file. This is the sheet where we store information previously extracted via this script, so that we can examine this data and only add **new** information to it
comb_df <- read.csv("farmers_r_sheet.csv")


# Change Link column to character type
comb_df$Link <- as.character(comb_df$Link)


# Use anti_join to get rows in scraped_table_df that are not in comb_df and bind them with comb_df. This is how we ensure we are only adding new information to our data base, and not duplicating information we previously added. The unique id we use for matching purposes is the "Nomor_Perkara" (or "case number") column.
comb_df <- bind_rows(scraped_table_df, anti_join(comb_df, scraped_table_df, by = 'Nomor_Perkara'))

# Converting "Tanggal_Register" column to date format
comb_df$Tanggal_Register <- as.Date(comb_df$Tanggal_Register, "%d %b %Y")

# Writing the newly updated data back to our working directory
write.csv(comb_df, "farmers_r_sheet.csv", row.names = FALSE)
