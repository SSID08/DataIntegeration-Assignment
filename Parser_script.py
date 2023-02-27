import argparse
import os
import sqlite3

parser=argparse.ArgumentParser()

parser.add_argument(
    'db', type=str,nargs='?',
    help="Path to the relevant empty sqlite database",
    default='../VCFdb.sqlite'
)

parser.add_argument(
    'input_path', type=str,nargs='?',
    help="Path to the folder containing the relevant VCF files",
    default='../VCF files'
)

args=parser.parse_args()


#Main method
with sqlite3.connect(args.db) as db:
    file_id=1
    cursor=db.cursor()
    for file in [x for x in os.listdir(args.input_path) if x.endswith('.vcf')]:
    #Add file to table 
        query_file_insert=f'INSERT INTO files VALUES({file_id}, "{file}");'
        try:
            cursor.execute(query_file_insert)
        except Exception as e:
            print(e)
            break
        #conn.commit()
        file_id+=1
        ## Tell user if table already existed
        table_name=file.rstrip(".vcf")
        query_create_table=f'CREATE TABLE IF NOT EXISTS {table_name} (Chromosome TEXT NOT NULL, Position INTEGER NOT NULL, ID INTEGER DEFAULT 1, Reference TEXT NOT NULL, Alternate TEXT NOT NULL, Qual INTEGER, Filter TEXT, Info TEXT,GT TEXT,GQ TEXT,DP TEXT,PRIMARY KEY (Chromosome, Position));'
        try:
            cursor.execute(query_create_table)
        except Exception as e:
            print(e)
            break
    #create Table in database for this file 
        vcf=open(os.path.join(args.input_path,file),'r')
        with vcf as fr:
            for line in fr:
                if not line.startswith('#'):
                    line.rstrip('\n')
                    split_line=line.split('\t')
                    if not split_line[2].isdigit():
                        id_val=1
                    else:
                        id_val=split_line[2]
                    format_split=split_line[9].split(":")
                    data_insert_query=f'INSERT INTO {table_name} VALUES("{split_line[0]}",{split_line[1]},{id_val},"{split_line[3]}","{split_line[4]}",{split_line[5]},"{split_line[6]}","{split_line[7]}","{format_split[0]}","{format_split[1]}","{format_split[2]}");'
                    try:
                        cursor.execute(data_insert_query)
                    except Exception as e:
                        print(e)
                        exit("Error occured while import. This most likely has to do with the input file format of your vcf files. Please recheck your files")
db.close()

