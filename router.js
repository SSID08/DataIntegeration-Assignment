//import required packages
const sqlite3 = require('sqlite3').verbose(); 
const express = require('express');
const router = express.Router();
var db;
const prompt=require('prompt-sync')();
const fs = require('fs');

//prompt user for database path
var db_path=prompt('Please provide path for the database file. If left empty, the default database in the project folder will be used');

//connect to relevant database depending on user input
if(db_path==''){
    db=new sqlite3.Database('../VCFdb.sqlite');
}
else if (fs.existsSync(db_path)&db_path.endsWith('.sqlite')){
    db=new sqlite3.Database(db_path);
}
else{
    throw Error('The file path you have inputted does not exist. Please restart the server and input the correct path');
}

//Create function to log every time a request is recieved at this address
router.use(function (req, res, next) {
    console.log('Request recieved');
    next();
});

//Get request to deal output list of files present in database
router.get('/file_list', function (req, res) {
    console.log("outputting JSON object with list of VCf datasets in the SQLlite database.")
    const query = 'SELECT file_name FROM files;'; //create query to extract file_name column from files table
    db.all(query, [], function (err, rows) { // execute query 
        if (err) {
            throw err;
        }
        var return_array = new Array(); //initialise new array to store return value
        rows.forEach(element => {
            return_array.push(element['file_name']) //store row values in array
        });
        res.send(return_array);//send array back to user in the response object
    })
});

//Get request to send table to R api


//Get request to outuput total variant counts for each chromosome of each file
router.get('/variant_counts', function (req, res) {
    //initialise variables to be used to formulate custom query
    var file_name;
    var chr;
    var type= req.query.type || 'Total_count';
    //Customise the file_name variable to be able to deal with missing values
    if (req.query.file_name){
        file_name= '= '.concat('"'+req.query.file_name+'"');
    }
    else{
        file_name='IS NOT NULL';
    }
    //customise the chr variable to be able to deal with missing values
    if(req.query.chromosome){
        chr = '= '.concat('"'+req.query.chromosome+'"');
    }
    else{
        chr= 'IS NOT NULL';
    }
    //customise the type variable to be able to deal with missing values and different types of values
    if(req.query.type){
        if (req.query.type.toLowerCase().includes('indel')){
            type='Indel_count';
        }
        else if(req.query.type.toLowerCase().includes('snp')){
            type='SNP_count';
        }
        else{
            type='Total_count';
        }
    }

    const query=`SELECT File,Chromosome,${type} FROM count_table WHERE File ${file_name} AND Chromosome ${chr};`;//create SQL query

    try{//execute sql query in try catch block
        db.all(query, [], function (err, rows) {
            if (err) {
                throw err;
            }
            //var return_array=new Array();
            //rows.forEach(element=>{return_array.push(element['File'])})
            res.json(rows)//output rows as json object
        });}
        catch(err){
            res.send('Error occurred while executing database query. Please check input format');
        }
});

//get request to output specific rows from vcf files requested by the user
router.get('/variant_information/:file_name/:chromosome/:positions/:type?', function (req, res) {
    //initialise variables to deal with multiple url input parameters
    const file_name = req.params.file_name;
    const chromosome = req.params.chromosome;
    const positions = req.params.positions;
    const start = positions.split("-").at(0);
    const end = positions.split("-").at(1);
    const type = req.params.type;
    var query = `SELECT * FROM ${file_name} WHERE Position>=? AND Position<=? AND Chromosome=?`//create custom SQL query
    //append SQL query depending on user input parameters
    if (!type) {
        query = query.concat(" ;");
    }
    else if (type.toLowerCase().includes("indel")) {
        query = query.concat(" AND length(Reference)!=length(Alternate);");
    }
    else if (type.toLowerCase().includes("snp")) {
        query = query.concat(" AND length(Reference)==length(Alternate);");
    }
    else {
        query = query.concat(" ;");
    };
    const parameters = [start, end, chromosome];//set parameters to execute SQL query
    try{
    db.all(query, parameters, function (err, rows) {
        if (err) {
            throw err;
        }
        res.json(rows);
    });}
    catch(err){
        res.send('Error occurred while executing database query. Please check input format');
    }
});

const request = require('request');//import package to send url requests from the server-end

//get request to output an array of variant density 
router.get('/variant_density/:file_name/:chromosome',function (req, res) {
    //initialise variables to deal with input url parameters
    const genome_name = req.params.file_name;
    const chr = req.params.chromosome;
    var ws = req.query.window_size || 1000000;
    var type = req.query.type || null;
    //create custom url query to send to the API hosted using plumber 
    const url = `http://127.0.0.1:3001/variant_density?genome_name=${genome_name}&chr=${chr}&window_size=${ws}&type=${type}`;
    request(url,function(err,response,body){//callback function sending at get request to the Plumber API
        if (err){
            throw err;
        }
        var return_array = new Array();//initialise array to send back a response object 
        Array.from(JSON.parse(body)).forEach(element => {//parse the response of the nested callback function 
            var position=element['Positions'];
            var count=element['Density count'];
            return_array.push(`Positions ${position} -> have a variant count of : ${count}`);//append to the object to be used to send information back to the user
        }); 
        res.send(return_array);// send response object
    });
});

// get request to force download of plot of variant density 
router.get('/variant_density_plot/:file_name/:chromosome',function(req,res){
    //initialise variables depending on user input
    const genome_name = req.params.file_name;
    const chr = req.params.chromosome;
    var ws = req.query.window_size || 1000000;
    var type = req.query.type || null;
    //initialise url string to connect to the API hosted in Plumber
    const url = `http://127.0.0.1:3001/variant_density_plot?genome_name=${genome_name}&chr=${chr}&window_size=${ws}&type=${type}`;
    var output_file_name=`Genome:${genome_name}_Chromosome:${chr}_per:${ws}_${type}_density_plot.png`;//set custom name for the png file that will be downloaded
    if(!type){
        output_file_name=`File_name:${genome_name}_Chromosome:${chr}_per:${ws}_TotalVariant_density_plot.png`;//change name of output file if no type is specified
    }
     request(url, {endcoding:'binary'},function(err, response, body) {//send get request to the Plumber API to enable creation of the plot
        if (err) {
            throw err;
        }
        res.download(body,output_file_name);//download the binary file that is sent as a response to the nested call-back function
    });
});

module.exports = router;//allow the app.use() method in server.js to access the router object
