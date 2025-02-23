**FREE

///
// Integration to noxDB - Note it requires the NOXDB installed
// You need to run the SQL scripts in "demo.sql" by ACS to have the test data
//
//
// Start it:
// ADDLIBLE ILEASTIC
// SBMJOB CMD(CALL PGM(NOXDBPROD)) JOB(NOXDBPROD) JOBQ(QSYSNOMAX)  ALWMLTTHD(*YES)        
// 
// The web service can be tested with the browser by entering the following URL:
//
// http://my_ibm_i:44025/router/product/meta
// http://my_ibm_i:44025/router/product/find
//
// @info: It requires your RPG code to be reentrant and compiled for 
//        multithreading. Each client request is handled by a seperate thread.
///
   
ctl-opt copyright('Sitemule.com  (C), 2018-2022');
ctl-opt decEdit('0,') datEdit(*YMD.) ;
ctl-opt debug(*yes) bndDir('ILEASTIC':'NOXDB');
ctl-opt thread(*CONCURRENT);
ctl-opt main(main);


/include ./headers/ILEastic.rpgle
/include ./noxdb/headers/jsonParser.rpgle

// -----------------------------------------------------------------------------
// Program Entry Point
// -----------------------------------------------------------------------------     
dcl-proc main;

    dcl-ds config likeds(IL_CONFIG);
    config.port = 44025; 
    config.host = '*ANY';

    il_addRoute(config : %paddr(product_meta)     : IL_GET : 'router/product/meta');
    il_addRoute(config : %paddr(product_find)     : IL_ANY : 'router/product/find');
    il_addRoute(config : %paddr(product_update)   : IL_ANY : 'router/product/update');
    il_addRoute(config : %paddr(product_delete)   : IL_ANY : 'router/product/delete');
    il_addRoute(config : %paddr(serveStaticFiles) : IL_ANY : '.*');
    il_listen(config);
 
end-proc;

// -----------------------------------------------------------------------------
// Servlet callback implementation
// -----------------------------------------------------------------------------     
dcl-proc serveStaticFiles;

    dcl-pi *n;
        request  likeds(IL_REQUEST);
        response likeds(IL_RESPONSE);
    end-pi;

    dcl-s file varchar(256);
    dcl-c FILE_NOT_FOUND  '1';

    // Get the resource a.k.a. the file name 
    file = il_getRequestResource(request);

    // No resource then default to: index.html
    if file = '/';
        file = 'index.html';
    endif;

    // You can now concatenate the file to point to 
    // any place on the IFS where your web content are located. i.e.:
    file = '/prj/ileastic/examples/client/' + file;
    
    // Serve any static files from the IFS
    if (FILE_NOT_FOUND = il_serveStatic (response : file));
        response.status = 404;
        il_responseWrite(response : 'File ' + file + ' not found');
    endif;

end-proc;

// -----------------------------------------------------------------------------
dcl-proc product_meta;

    dcl-pi *n;
        request  likeds(IL_REQUEST);
        response likeds(IL_RESPONSE);
    end-pi;

    dcl-s  pMeta      	pointer;
    dcl-ds itColumns    likeds(json_iterator);

	
    pMeta = json_sqlGetMeta  ('-
        select * - 
        from microdemo.ilProducts -
    ');

    // Add which column is the primary key
    itColumns = json_setIterator(pMeta);
    dow json_forEach(itColumns);
        if json_getStr (itColumns.this: 'name') = 'id';
            json_setBool (itColumns.this : 'isIdColumn' : *ON);
        endif;
    enddo;


    // Use the stream to input data from noxdb and output it to ILEastic 
    il_responseWriteStream(response : json_stream( pMeta));
    json_delete (pMeta);


end-proc;
// -----------------------------------------------------------------------------
dcl-proc product_find;

    dcl-pi *n;
        request  likeds(IL_REQUEST);
        response likeds(IL_RESPONSE);
    end-pi;

    dcl-s  pResultSet     	pointer;
    dcl-s  pInput       	pointer;
    dcl-s  payload          varchar(4096);
    dcl-s  sqlStmt        	varchar(4096);
    dcl-s  start  			int(10);
    dcl-s  limit  			int(10) inz(-1);

    payload = il_getRequestContent (request );
    pInput = json_parseString( payload); 

    sqlStmt = ('+
        select * +
        from microdemo.ilProducts +
    ');

    addWhereClause   ( sqlStmt : pInput);
    addOrderByClause ( sqlStmt : pInput);

    start   =  json_getNum(pInput : 'start' );
    limit   =  json_getNum(pInput : 'limit' );

    pResultSet = json_sqlResultSet   (
        sqlStmt
        : start + 1
        : limit
        : JSON_META + JSON_TOTALROWS
    );

    // Use the stream to input data from noxdb and output it to ILEastic 
    il_responseWriteStream(response : json_stream( pResultSet));
    json_delete (pResultSet);
    json_delete (pInput);


end-proc;

//  -------------------------------------------------------------------- 
//   Normal proccedure for adding the " order by " clause to the sql 
//  -------------------------------------------------------------------- 
dcl-proc addWhereClause;

    dcl-pi *n;
        sqlStmt             varchar(4096); 
        pInput 				pointer value;
    end-pi;

    dcl-ds itColumns        likeds(json_iterator);
    dcl-s  search 	   		varchar(256);
    dcl-s  concat     		varchar(16);
    dcl-s  pMeta 			pointer;
    dcl-s  flds 			varchar(4096);

    search =  json_getStr(pInput : 'search');

    // When the client has a "where" we simply use that 
    // In production - take care !! this might be prone to "SQL injections"
    if search  > '';

        pMeta = json_sqlGetMeta  ('-
                select * - 
                from microdemo.ilProducts -
        ');
        itColumns = json_setIterator(pMeta);
        concat = '' ;

        dow json_forEach(itColumns);
            flds += concat +  'char(' + json_getStr(itColumns.this:'name') + ')';
            concat =  ' concat ';
        enddo;
        json_delete(pMeta);

        sqlStmt += ' where lower(' + flds + ') like ' 
            + %lower(strQuot('%' + search+ '%'));
    endif;

end-proc;
// --------------------------------------------------------------------
// Normal proccedure for adding the " order by " clause to the sql
// --------------------------------------------------------------------
dcl-proc addOrderByClause;

    dcl-pi *N;
        sqlStmt             varchar(4096); 
        pInput 				pointer value;
    end-pi;

    dcl-s  sort  	   		varchar(4096);

    sort    =  json_getStr(pInput : 'sort');

    // Concat the order by:
    if sort > '';
        sqlStmt += ' order by ' + sort;
    endif; 


end-proc;

//  -------------------------------------------------------------------- 
//  update row
//  -------------------------------------------------------------------- 
dcl-proc product_update ;

    dcl-pi *n;
        request  likeds(IL_REQUEST);
        response likeds(IL_RESPONSE);
    end-pi;

    dcl-s  pInput       pointer;
    dcl-s  err			ind;
    dcl-s  pOutput		pointer;
    dcl-s  pRow			pointer;
    dcl-s  payload      varchar(4096);
    dcl-s  id           int(10);


    payload = il_getRequestContent (request );
    pInput = json_parseString( payload); 

    // asume ok;
    pOutput = json_successTrue();

    // Find the sql rodata within my input
    pRow = json_locate (pInput : 'row');

    ensureKey (pRow);
    id =  json_getInt  ( pRow : 'id') ;

    // update using object as the row 
    err = json_sqlUpsert (                                                        
        'microdemo.ilProducts'            // table name                                     
        :pRow                  	        // row in object form {a:1,b:2} etc..             
        :'id = ' + %char(id)  // the key 
    );                                                                            	

    if err;
        json_setBool (pOutput : 'success' : *OFF);
        json_setStr  (pOutput : 'msg'    : json_Message(*NULL));
    endif;

    // Use the stream to input data from noxdb and output it to ILEastic 
    il_responseWriteStream(response : json_stream( pOutput));
    json_delete (pOutput);
    json_delete (pInput);


end-proc;
// ------------------------------------------------------------------- 
// if the key is null, it is a insert operation
// then find the next key 
// ------------------------------------------------------------------- 
dcl-proc ensureKey;

    dcl-pi *n;
        pInput 			pointer value;
    end-pi;

    dcl-s pTemp			pointer;

    // If no key is supplied, then create a new one, in steps +10 
    if json_getint ( pInput : 'id') = 0;
        pTemp = json_sqlResultRow ('-  
            select max(id) + 10  as id -
            from microdemo.ilProducts -
        ');
        json_copyvalue (pInput: 'id' : pTemp: 'id');
        json_delete (pTemp);
    endif;

    // the ExtJs default "ID" does not make sense here;
    //json_delete(json_locate(pInput:'id'));

end-proc;

//  -------------------------------------------------------------------- 
//  delete row
//  -------------------------------------------------------------------- 
dcl-proc product_delete;

    dcl-pi *n;
        request  likeds(IL_REQUEST);
        response likeds(IL_RESPONSE);
    end-pi;

    dcl-s  err			ind;
    dcl-s  pOutput		pointer;
    dcl-s  pInput       pointer;
    dcl-s  id      int(10);
    dcl-s  payload      varchar(4096);

    payload = il_getRequestContent (request );
    pInput = json_parseString( payload); 


    // asume ok;
    pOutput = json_successTrue();

    id = json_getint ( pInput : 'key');

    // delete using input object as the template data
    err = json_sqlExec (                                                        
        'Delete from microdemo.ilProducts where id = ' + %char(id) 
    );                                                                            	

    if err;
        json_setBool (pOutput : 'success' : *OFF);
        json_setStr  (pOutput : 'msg'    : json_Message(*NULL));
    endif;

    // Use the stream to input data from noxdb and output it to ILEastic 
    il_responseWriteStream(response : json_stream( pOutput));
    json_delete (pOutput);


end-proc;


//  -------------------------------------------------------------------- 
//  escape quotes so it comes in pars 
//  -------------------------------------------------------------------- 
dcl-proc strQuot ;

    dcl-pi *n varchar(256);
        input  varchar(256)  const options(*varsize);
    end-pi;

    return '''' + %scanrpl  ('''':'''''': input) + ''''; 

end-proc;
