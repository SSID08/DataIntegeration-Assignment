#Import required modules
library(RSQLite)
library(DBI)
library(plumber)
library(httr)
library(ggplot2)
library(tidyverse)
library(dplyr)
library(jsonlite)

#Prompt user to set path to SQL database they would like to use
Path_to_SQL_database=readline(prompt="Enter path to SQL database. If left empty it will connect to the default database in the project folder")
final_path_to_SQL=''

#Set path to the SQL database to be used based on user input
if(Path_to_SQL_database==''){
  final_path_to_SQL='../VCFdb.sqlite'
}else{
  if(file.exists(Path_to_SQL_database)&endsWith(Path_to_SQL_database,'.sqlite')){
    final_path_to_SQL=Path_to_SQL_database
  }else{
    stop('The given database does not exist')
  }
}

#Create function to populate the SQL database
populate_count_table=function(){
  #Create empty dataframe
  count_df=data.frame(File=character(0),Chromosome=numeric(0),Indel_count=numeric(0),SNP_count=numeric(0),Total_count=numeric(0))
  #Connect to the SQL database specified at path
  conn=dbConnect(SQLite(),final_path_to_SQL)
  file_list=as.vector(dbGetQuery(conn,'SELECT * FROM files;'))$file_name#create list of files in the files table of the SQL database
  for (file in file_list){#iterate through the list of files
    table_name=gsub('.vcf','',file)#Set table name after removing extension
    chr=1#Initialise chromosome to 1
    max_chr=strtoi(dbGetQuery(conn,paste('SELECT max(Chromosome) FROM',table_name,';')))#Get the maximum chromosome present in the specfic file
    while (TRUE){#Enter while loop
      #Create dataframe from query 
      df=data.frame(dbGetQuery(conn,paste('SELECT Chromosome,Reference,Alternate FROM',table_name,'WHERE Chromosome=',chr,';')))
      #Add columns to the dataframe representing if the row is a snp or an indel
      df=df%>%mutate(SNP=ifelse(nchar(Reference)==nchar(Alternate),1,0),Indel=ifelse(nchar(Reference)!=nchar(Alternate),1,0))
      # Get Sum the indel column
      total_indel=sum(df$Indel)
      # Get sum of the SNP column
      total_SNP=sum(df$SNP)
      #Set total variants to be the sum of total SNP and indel count
      total_var=total_indel+total_SNP
      #Add to the count_df rows with containing information on variant counts of each chromosome in each file
      count_df=count_df%>%add_row(File=file,Chromosome=chr,Indel_count=total_indel,SNP_count=total_SNP,Total_count=total_var)
      chr=chr+1#Increase chromosome by 1
      if(chr>max_chr){break}#break out of while loop if end of file reached
    }
  }
  count_df$Chromosome=as.character(count_df$Chromosome)#Change type of chromosome column
  insert_statement=sqlAppendTable(con = conn,table = "count_table",values =count_df,F)#Insert values to count_table in the SQL database
  tryCatch({dbExecute(conn,insert_statement)},error=function(e){print ('Function attempted to repopulate existing database. Error was caught and dealt with.')})#Catch error if attempting to populate an existing table
  dbDisconnect(conn = conn)}#Disconnect from database

populate_count_table()#Call function to populate database


variant_density_maker=function(genome_name,chromosome,window_size=100000,type='null'){#function to calculate variant density
  conn=dbConnect(SQLite(),final_path_to_SQL)#Connect to sqlite database specified at path
  my_df=data.frame(dbGetQuery(conn,paste("SELECT Chromosome,Position,Reference,Alternate FROM",genome_name,"WHERE Chromosome=",chromosome)))#Create dataframe from sqlite query 
  my_df=my_df%>%mutate(SNP=ifelse(nchar(Reference)==nchar(Alternate),1,0),Indel=ifelse(nchar(Reference)!=nchar(Alternate),1,0))#Add to specific columns if row is an indel or a snp
  max_val=max(my_df$Position)#Get maximum position of particular chromosome in the relevant vcf file
  #Initialise empty arrays to store data
  count=c()
  count_names=c()
  if(is.character(window_size)){
  window_size=strtoi(window_size)}
  i=0#initialise position marker to 0
  while(i<max_val){#Enter while loop as long as position marker is not greater than the maximum position value of chromosome
    temp_df=my_df%>%filter(Position>=i & Position<=i+window_size)#Create temporary dataframe to store values within the specific window
    count_names=c(count_names,paste(i,i+window_size,sep = '-'))#Append to names vector
    if(grepl('null',tolower(type))|grepl('total',tolower(type))){#Append to count vector different values depending on value of the type variable
      count=c(count,sum(temp_df$Indel)+sum(temp_df$SNP))
    }
    else if (grepl('indel',tolower(type))){
      count=c(count,sum(temp_df$Indel))
    }
    else if(grepl('snp',tolower(type))){
      count=c(count,sum(temp_df$SNP))
    }
    i=i+window_size#increment position counter by window_size
  }
  names(count)=count_names#Set names of the vector
  dbDisconnect(conn = conn)#Disconnect the open connection to the sqlite database
  return(count)#return the count vector
}


#*@get /variant_density
function(genome_name,chr,window_size=100000,type='null'){#Callback function to deal with get requests at this address
  out_array=variant_density_maker(genome_name,chr,window_size,type)#set variable to capture return value of the variant_density_maker function
  out_df=out_array%>%enframe(name = 'Positions',value = 'Density count')#Create dataframe from named vector
  return(out_df)#return the dataframe
}

#*@get /variant_density_plot
#*@serializer contentType list(type='image/png')
##png list(width=6,height=6,units="in",res=800)
function(genome_name,chr,window_size=100000,type='null'){#callback function to deal with get request at this address
  out_array=variant_density_maker(genome_name,chr,window_size,type)#set variable to capture return value of the variant_density_maker function
  out_df=out_array%>%enframe(name = 'Positions',value = 'Density_count')#Create dataframe from named vector
  if(is.character(window_size)){
    window_size=strtoi(window_size)}
  end_position=window_size*length(out_df$Positions)#Get the highest position value in the dataframe
  tmp=tempfile()#Create a temporary file to save the plot
  #Create a ggplot and assign it to a variable
  return_plot=ggplot(out_df,aes(x=seq(1,length(Positions),1),y=Density_count))+geom_bar(stat = 'identity',alpha=.5)+stat_smooth(geom='line', alpha=0.5, se=FALSE,col='red')+xlab(paste('Chromosome',chr,'Positions (in kilobases)',sep=' '))+ylab(paste('Variants per',window_size,sep=' '))+scale_x_continuous(breaks=seq(0,length(out_df$Positions),length.out=10),labels=round(seq(0,end_position,length.out=10)/1000,0))
  return_plot=return_plot+ylim(c(0,NA))#Set the ylimit of the plot object
  ggsave(filename = tmp,plot = return_plot,device = 'png',width = 6,height = 6,units = 'in',dpi = 300)#Save the plot in the temporary file
  return(tmp)}#Return the temporary file
  #png(,width=6,height=6,units="in",res=800)
  #print(return_plot)}

