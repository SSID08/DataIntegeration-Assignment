const express=require('express');//import the required package
const router=require('./router');//import the router object from the router.js script
const app=express();//create an object of from the express module
const port=2000;//set the port to host the server
app.listen(port,function(){console.log(`Application deployed on port ${port}`);});//deploy server
app.use('/api',router);//mount router on the server 
