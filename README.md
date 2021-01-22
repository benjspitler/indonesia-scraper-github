## Using RSelenium to scrape the web for court cases in Indonesia

This is a project I'm working on for a journalist friend who investigates environmental justice issues in Southeast Asia. One such issue relates to prosecutions of smallholder farmers in Indonesia. Indonesia has a major problem with air pollution, and in particular smoky haze, which blankets parts of Southeast Asia each year. Much of this haze originates in Indonesia, on the islands of Sumatra and Borneo, and then wafts across the water to Malaysia and Singapore; the haze is a source of diplomatic tension in the region, as well as a major health hazard.

The source of this haze, in part, is deliberate burning to clear land area in Sumatra and Borneo. It is true that small farmers in these places have practiced swidden agriculture for generations, but the large palm oil and pulpwood conglomerates based in Indonesia also use these tactics on a much larger scale to make space for expanding their plantations. Nevertheless, the Indonesian judiciary continues to prosecute small farmers for burning land, while relatively few plantation concerns are punished.

Information regarding the prosecution of farmers for burning is posted on a series of websites hosted by Indonesia's judiciary; each website pertains to a different federal district of Indonesia, and lists prosecutions and court cases for that district:

<img src="images/indon_search_screenshot.png?raw=true"/>

Compared to the data disclosure practices of governments in other parts of the world where I have worked (especially the Middle East), the Indonesian government's approach isn't terrible. When you navigate to a court website, you can search for a term and return an organized table that summarizes all of the search results and provides links for more detail. That said, there are still quite a few barriers here to easily extracting and processing real time data about court cases. For one thing, these results tables are not downloadable in any kind of PDF or Excel file format; they're just static HTML pages. Additionally, there's no filtering functionality, so the only way to access results is through keyword search. As a result journalists and rights activists documenting prosecutions of small farmers spend a lot of time on these websites, entering search terms, scrolling through results, and manualy entering data. I wanted to automate this process so they always have an up-to-date database showing the current state of these court cases.

### Scraping packages

Prior to starting this project, I had only done webscraping [through the rvest package](https://benjspitler.github.io/ksa_scraper). This project is a bit more complex, because the search results on these court websites are dynamically retrieved with javascript. This means that when you perform a search, the page URL itself does not change, so you can't enter a search results-specific URL and just scrape that page. Instead, I used the RSelenium package, which essentially allows you to run a dummy browser within an R session. This has applications not only in web scraping, but also in software testing. For web scraping purposes, you can actually use R code to direct your R session to open a browser, enter a search term, click the search button, and download the HTML from the dynamically-retrieved results page, even though the URL never changes. Then you can use rvest to actually scrape the contents of the HTML. Pretty cool!

### Search strategy

The full code for this project is below, but I'll offer a description here of how I chose search terms, and which court website I am searching. In the screenshot above, you see a table with a number of columns, one of which is titled "Klasifikasi Perkara", which means "Case Classification." There are two principal case classifications pertaining to land burning cases: "Kebakaran Hutan", which means "Forest Burning", and "Hal-hal yang mengakibatkan kerusakan dan pencemaran lingkungan", which means "Causing damage and enviromental pollution". These two case classifications are the search terms used to narrow search results to land burning cases.

Another wrinkle is that, as stated above, each district court has its own separate website, and there are hundreds of such districts in Indonesia. Land burning cases are mostly concentrated in Sumatra and Borneo, but you still need to examine 27 websites to find all relevant results. So the script below is an example that crawls one court website (for the Pangkalan Bun district) for results for the "Kebakaran Hutan" search term. I'm still working on how exactly to make this script to scrape all 27 websites for both search terms sequentially. For now though, this script allows for the easy extraction of relevant case information from any court website through the manipulations of small bits of text within the R code. The code below 1. navigates to a court website, 2. searches for a specific term, 3. downloads the relevant information from the resulting search results table, and 4. adds that information to an existing database (in the form of a .csv file) only if the scraped information is new, i.e. does not already exist in the database.


```javascript
install.packages("RSelenium")
install.packages("tidyverse")

library(RSelenium)
library(rvest)
library(stringr)
library(tidyverse)
library(dplyr)

# Initiate Selenium browser.
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
```
