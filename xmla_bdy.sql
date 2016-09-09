create or replace PACKAGE BODY               XMLA_MDX
/*
Package : Extracts the Essbase data via XMLA services and presents in a Relational Table Format. A portion of this package 
          ( getXmlaData function ) is based on Evgeniy.Rasyuks essbase-plsql-interface package.

Changes :  Evgeniy.Rasyuk : ( Original XMLA query (getXmlaData) to get the essbase data( essbase-plsql-interface )
           Sanjay Ganvkar : Added the XML Transformation process ( extract_xml_to_string ) to transform the XML tuples/Ordinal
			                   into a relational format.
			  Sanjay Ganvkar : 21st Sep 2015 -- Included Meta Character conversion & replaced with &amp1

 
*/
AS
   G_XMLA_FAULT_STRING_CHECK VARCHAR2(9) := 'faultcode';
	G_XMLA_TIMEOUT NUMBER := 600;  -- Seconds
	G_META_CHAR_FROM_1 VARCHAR2(1) := '&';
	G_META_CHAR_TO_1 VARCHAR2(5) := '&amp;';
	
	FUNCTION translate_meta_chars
	(
		p_str  VARCHAR2
	) RETURN VARCHAR2
	IS
	BEGIN
	   RETURN REPLACE(p_str,G_META_CHAR_FROM_1 , G_META_CHAR_TO_1);
	
	END translate_meta_chars;
	
	PROCEDURE insert_debug (
		vXmlaBody CLOB)
	AS
		PRAGMA AUTONOMOUS_TRANSACTION;
	BEGIN
	 NULL;
	  --DELETE XMLA_MDX_DEBUG;
 	 --INSERT INTO XMLA_MDX_DEBUG   VALUES ( vXmlaBody);
	 -- 	COMMIT;
	END insert_debug;
 
	FUNCTION getMDXData(
		p_mdx_query VARCHAR2,
		p_aps_url VARCHAR2,
		p_essbase_server VARCHAR2,
		p_essbase_user VARCHAR2,
		p_essbase_password VARCHAR2,
		p_suppress_missing VARCHAR2 DEFAULT 'N'
	) RETURN XMLTYPE 
	IS
		v_xml_data XMLTYPE;

	BEGIN
 
		v_xml_data := getXmlaData( translate_meta_chars(p_mdx_query), p_aps_url, p_essbase_server, p_essbase_user, p_essbase_password );
	 
		RETURN ( xmltype.createxml(extract_xml_to_string (v_xml_data, p_suppress_missing)) );
		
	EXCEPTION
		WHEN OTHERS THEN
			RAISE;
	END getMDXData;

	FUNCTION getXmlaData(
		p_mdx_query VARCHAR2,
		p_aps_url VARCHAR2,
		p_essbase_server VARCHAR2,
		p_essbase_user VARCHAR2,
		p_essbase_password VARCHAR2
	) RETURN XMLTYPE 
	IS
		pTextBuffer     VARCHAR2(32767);
		vXmlaBody   VARCHAR2(32767);
		vTextBuffer CLOB := NULL;
		vUtlHttpReq UTL_HTTP.req;
		vUtlHttpResp UTL_HTTP.resp;
		vUtlHttpConnRecord UTL_HTTP.connection;
		vClobErrBuffer CLOB;
		vHaveData NUMBER := 0;
		vIsEndOfHttp NUMBER :=0;
 
	BEGIN
		DBMS_LOB.createtemporary(vTextBuffer, FALSE);

	   vXmlaBody := get_xmla_request_string(p_mdx_query, p_essbase_server);

		UTL_HTTP.SET_DETAILED_EXCP_SUPPORT (true);
		BEGIN

			UTL_HTTP.set_persistent_conn_support(true,4);
			--  vUtlHttpConnRecord.host:='localhost';
 

			UTL_HTTP.set_transfer_timeout(G_XMLA_TIMEOUT); --it's not supported in 11 version
			-- [ID 760664.1]
			vUtlHttpReq := UTL_HTTP.begin_request(p_aps_url, 'POST');--, 'HTTP/
			-- 1.0');
			UTL_HTTP.set_authentication(vUtlHttpReq, p_essbase_user, p_essbase_password);
			UTL_HTTP.set_persistent_conn_support(vUtlHttpReq, TRUE);
			UTL_HTTP.set_header(vUtlHttpReq, 'content-type', 'text/xml; charset=windows-1251');
			UTL_HTTP.set_header(vUtlHttpReq, 'content-length', LENGTH(vXmlaBody));
			UTL_HTTP.write_text(vUtlHttpReq, vXmlaBody);
			vUtlHttpResp := UTL_HTTP.get_response(vUtlHttpReq);

		EXCEPTION
			WHEN OTHERS THEN
 
				raise_application_error(-20101, utl_http.get_detailed_sqlerrm);

		END;
		IF ( UTL_HTTP.HTTP_OK = vUtlHttpResp.status_code ) THEN
			BEGIN
				LOOP
					UTL_HTTP.read_text(vUtlHttpResp, pTextBuffer, 32766);
					DBMS_LOB.writeappend (vTextBuffer, LENGTH(pTextBuffer), pTextBuffer);

				END LOOP;
			EXCEPTION
				WHEN UTL_HTTP.end_of_body THEN
 
					UTL_HTTP.end_response(vUtlHttpResp);
					 
 
					IF ( INSTR(vTextBuffer,G_XMLA_FAULT_STRING_CHECK) != 0 )
					THEN
						raise_application_error(-20115, vTextBuffer);  
					ELSE

						--RETURN  XMLTYPE.CREATEXML(translate_meta_chars(vTextBuffer));
						RETURN  XMLTYPE.CREATEXML(vTextBuffer);

					END IF;
				WHEN OTHERS THEN
 
					UTL_HTTP.END_RESPONSE (vUtlHttpResp);
 
					DBMS_LOB.freetemporary(vTextBuffer);
					raise_application_error(-20105, pTextBuffer);              
			END;
 
			END IF;
			UTL_HTTP.CLOSE_PERSISTENT_CONN (vUtlHttpConnRecord);
			UTL_HTTP.END_RESPONSE (vUtlHttpResp);
			DBMS_LOB.freetemporary(vTextBuffer);
			raise_application_error(-20110, vTextBuffer);
                        
	EXCEPTION
		WHEN NO_DATA_FOUND THEN
			UTL_HTTP.END_RESPONSE (vUtlHttpResp);
			DBMS_LOB.freetemporary(vTextBuffer);
			raise_application_error(-20107, vTextBuffer);      
		WHEN NO_DATA_NEEDED THEN
			UTL_HTTP.END_RESPONSE (vUtlHttpResp);
			DBMS_LOB.freetemporary(vTextBuffer);
			raise_application_error(-20108, vTextBuffer);      
		WHEN OTHERS THEN
			UTL_HTTP.END_RESPONSE (vUtlHttpResp);
			raise_application_error(-20109, vTextBuffer);
	END getXmlaData ;
        
	FUNCTION get_xmla_request_string ( p_mdx_query IN VARCHAR2, p_essbase_server IN VARCHAR2)
		RETURN VARCHAR2
	IS
	BEGIN
		RETURN (
		'<?xml version="1.0" encoding="windows-1251"?><SOAP-ENV:Envelope                              
		xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"                              
		xmlns:xsi = "http://www.w3.org/2001/XMLSchema-instance"                              
		xmlns:xsd="http://www.w3.org/2001/XMLSchema">                              
		<SOAP-ENV:Body>                              
		<Execute xmlns="urn:schemas-microsoft-com:xml-analysis"                              
		SOAP-ENV:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">                              
		<Command>
		<Statement>'
			  ||p_mdx_query||
			  '</Statement>            
		</Command>            
		<Properties>            
		<PropertyList>            
		<DataSourceInfo> Provider=Essbase;Data Source='
			  ||p_essbase_server||
			  ' </DataSourceInfo>       
		<Content>Data</Content>     
		<Format>      
		Tabular     
		</Format>       
		<AxisFormat>         
		TupleFormat      
		</AxisFormat>            
		<Timeout>30000</Timeout>            
		</PropertyList>            
		</Properties>            
		</Execute>            
		</SOAP-ENV:Body>            
		</SOAP-ENV:Envelope>'
		);

	END get_xmla_request_string;

	/* Main Procedure to transform the XML ordinals in a
	
		<TABLE><REC><Dimension1>Value</Dimension1><Dimension2>Value</Dimension2></REC><REC>..</REC></TABLE>
		
	   E.g <TABLE><REC><Country>US</Country><GP>1000</GP></REC><REC><Country>UK</Country><GP>2000</GP></REC> ...</TABLE>
		
	   Format.
		The procedure uses a sort of odometer concept to tie back the Cell ordinals to the Dimension Combinations, rotating the ordinal numbers of the non Axis0
		from a min-max dimension count.
		
		In case you want to do a Json transformation, tweak the opstr variable to get into a Json format 
		
	*/
	FUNCTION extract_xml_to_string (xmlData in XMLTYPE,p_suppress_missing IN  VARCHAR2) RETURN CLOB
	IS
		v_mdx_data CLOB;
		opstr VARCHAR2(4000);

		-- Dimension Summary
		TYPE dim_summ_type IS RECORD (  dim_cnt PLS_INTEGER , loop_count PLS_INTEGER, cur_index PLS_INTEGER, cur_value PLS_INTEGER );
		TYPE dim_summ_tab IS TABLE OF dim_summ_type INDEX BY PLS_INTEGER;
		dim_summ dim_summ_tab;

		-- Dimension Details
		TYPE dim_det_type IS RECORD (  axis PLS_INTEGER , Ordinal PLS_INTEGER , dimension  VARCHAR2(80), DimName VARCHAR2(80) );
		TYPE dim_det_tab IS TABLE OF dim_det_type INDEX BY VARCHAR2(80);
		dim_det dim_det_tab;
	
	   -- Cell Values
		TYPE CellOrd_CurPtr_Type IS TABLE OF VARCHAR2(80) INDEX BY PLS_INTEGER;
		CellOrd_ptr CellOrd_CurPtr_Type;

		cell_ordinal PLS_INTEGER := 0;

		tot_axis PLS_INTEGER := 0;
		axis0_count PLS_INTEGER := 0;
		tot_rows PLS_INTEGER := 0;

		
	BEGIN
	
		dbms_lob.createTemporary(v_mdx_data,true,dbms_lob.call);
 
		-- Prepare Cell Ordinals

       
		FOR rec1 in ( SELECT cell_ordinal , cell_ordinal_value  FROM TABLE ( extractValueInfoFromXML(xmlData)) )  
		LOOP
			CellOrd_ptr(rec1.cell_ordinal) := rec1.cell_ordinal_value;
		END LOOP;
		
		-- Dimension Details
 
		FOR rec2 in ( 
							SELECT 
									SUBSTR(Axist,5)||'_'||Ordinal akey , 
									TO_NUMBER(SUBSTR(Axist,5))  axis, 
									TO_NUMBER(Ordinal) Ordinal, 
									translate_meta_chars(replace(replace(replace(dimension,'['),']'),' ',''))   dimension, 
									translate_meta_chars(replace(replace(DimName,'['),']'))   DimName 									
									--REGEXP_REPLACE(dimension,'[ \[\]]','')   dimension, 
									--REGEXP_REPLACE(dimension,'\[\]]','')    DimName 
								FROM TABLE ( extractDimInfoFromXML(xmlData)) WHERE Axist like 'Ax%'  )     
		LOOP
			dim_det(rec2.akey).axis := rec2.axis;
			dim_det(rec2.akey).Ordinal := rec2.Ordinal;
			dim_det(rec2.akey).dimension := rec2.dimension;
			dim_det(rec2.akey).DimName := rec2.DimName;                    
		END LOOP;

		-- Get Dimension Count
 
      tot_rows := 1;
		tot_axis := 0;   
		FOR rec in ( SELECT TO_NUMBER(SUBSTR(Axist,5)) axis , count(1) cnt  FROM TABLE ( extractDimInfoFromXML(xmlData)) WHERE Axist like 'Ax%' GROUP BY TO_NUMBER(SUBSTR(Axist,5)) ,dimension ORDER BY TO_NUMBER(SUBSTR(Axist,5)))  
		LOOP
			dim_summ(rec.axis).dim_cnt := rec.cnt;

			IF rec.axis > 0 THEN     -- Exclude Axis0
				 tot_rows := tot_rows * rec.cnt;
			END IF;
			
			dim_summ(rec.axis).loop_count := (tot_rows/rec.cnt) ; -- Loop count
			dim_summ(rec.axis).cur_index := 1;
			dim_summ(rec.axis).cur_value := 0;	
			tot_axis := tot_axis + 1;
		END LOOP;
												  
		axis0_count := dim_summ(0).dim_cnt;

		cell_ordinal := 0;
	
		opstr := '<TABLE>';
		DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);

		FOR i IN 1..tot_rows 
		LOOP
			FOR j IN 0..axis0_count-1 -- 0..1
			LOOP

			   IF  ( NOT( upper(nvl(p_suppress_missing,'N')) = 'Y' AND NOT CellOrd_ptr.EXISTS(cell_ordinal) ) )
				THEN
					opstr := '<REC>';
					DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
					opstr := '<'||dim_det(0||'_'||j).dimension||'>'||dim_det(0||'_'||j).DimName|| '</'||dim_det(0||'_'||j).dimension||'>';
					DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
	 
					FOR  k IN 1..tot_axis-1 -- 1,,4
					LOOP
						opstr := '<'||dim_det(k||'_'||dim_summ(k).cur_value).dimension||'>'||dim_det(k||'_'||dim_summ(k).cur_value).DimName||'</'||dim_det(k||'_'||dim_summ(k).cur_value).dimension||'>';					
						DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
					END LOOP;
					
					IF ( CellOrd_ptr.EXISTS(cell_ordinal) )
					THEN
						opstr := '<CELLVALUE>'||CellOrd_ptr(cell_ordinal)||'</CELLVALUE>';
					ELSE
						opstr := '<CELLVALUE></CELLVALUE>';
					END IF;	 

					DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
					opstr := '</REC>';
					DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
				END IF;
				
				cell_ordinal := cell_ordinal + 1;
			END LOOP;
			
			FOR  t IN 1..tot_axis-1 -- rotate the cells
			LOOP
					dim_summ(t).cur_index := dim_summ(t).cur_index + 1;
 				
					IF ( dim_summ(t).cur_index > dim_summ(t).loop_count )
					THEN
						dim_summ(t).cur_index := 1;
						dim_summ(t).cur_value := dim_summ(t).cur_value + 1;
						IF ( dim_summ(t).cur_value = dim_summ(t).dim_cnt )
						THEN
							dim_summ(t).cur_value := 0;
						END IF;
					END IF;
			END LOOP;
			
		END LOOP;
		opstr := '</TABLE>';
		DBMS_LOB.writeappend(v_mdx_data, length(opstr), opstr);
		RETURN v_mdx_data;
	END extract_xml_to_string;
    
	/* Extract the Dimension Ordinals from the XML */	 
	FUNCTION extractDimInfoFromXML ( xmlData IN XMLTYPE ) RETURN dimRecTab PIPELINED
	IS
        dimRecT dimRecType;
	BEGIN    
		FOR REC IN (
				WITH table1 AS ( SELECT xmlData FROM dual )
				SELECT 
					Axisrs.Axist Axist, 
					TupleRS.Ordinal Ordinal,
					MemberRS.Dimension dimension,
					MemberRS.DimName DimName
					FROM  table1,
						XMLTABLE (
                            xmlnamespaces
                            ( default 'urn:schemas-microsoft-com:xml-analysis:mddataset',
                            'http://schemas.xmlsoap.org/soap/envelope/' as "SOAP-ENV",
                            'urn:schemas-microsoft-com:xml-analysis' as "m",
                            'http://www.w3.org/2001/XMLSchema-instance' as "xsi",
                            'http://www.w3.org/2001/XMLSchema' as "xsd"
                            ),      
                            '/SOAP-ENV:Envelope/SOAP-ENV:Body/m:ExecuteResponse/m:return/root/Axes/Axis'
                            PASSING xmlData
                            COLUMNS Axist VARCHAR2(10) PATH '@name',
                            XMLRS XMLTYPE PATH 'Tuples'
                        ) Axisrs ,
                        XMLTABLE (
                            xmlnamespaces
                            ( default 'urn:schemas-microsoft-com:xml-analysis:mddataset',
                            'http://schemas.xmlsoap.org/soap/envelope/' as "SOAP-ENV",
                            'urn:schemas-microsoft-com:xml-analysis' as "m",
                            'http://www.w3.org/2001/XMLSchema-instance' as "xsi",
                            'http://www.w3.org/2001/XMLSchema' as "xsd"
                            ),      
                            '/Tuples/Tuple'
                            PASSING Axisrs.XMLRS
                            COLUMNS Ordinal VARCHAR2(310) PATH '@Ordinal',
                             MEMBERS XMLTYPE PATH 'Member'
                        ) TupleRS ,
                        XMLTABLE (
                            xmlnamespaces
                            ( default 'urn:schemas-microsoft-com:xml-analysis:mddataset',
                            'http://schemas.xmlsoap.org/soap/envelope/' as "SOAP-ENV",
                            'urn:schemas-microsoft-com:xml-analysis' as "m",
                            'http://www.w3.org/2001/XMLSchema-instance' as "xsi",
                            'http://www.w3.org/2001/XMLSchema' as "xsd"
                            ),      
                            '/Member'
                            PASSING TupleRS.MEMBERS
                            COLUMNS Dimension VARCHAR2(310) PATH '@Hierarchy',
                             DimName VARCHAR2(310) PATH 'UName'
                        ) MemberRS        
		)
		LOOP
			dimRecT.Axist := rec.Axist;
			dimRecT.Ordinal := rec.Ordinal;
			dimRecT.dimension := rec.dimension;
			dimRecT.DimName := rec.DimName;
			PIPE ROW( dimRecT);
		END LOOP;
        
	END extractDimInfoFromXML;

	/* Extract the Cell Ordinals from the XML */
	FUNCTION extractValueInfoFromXML ( xmlData IN XMLTYPE ) RETURN cell_ord_tab PIPELINED
	IS
		ordRecT cell_ord_rec_type;
	BEGIN    
		FOR REC IN (
            WITH table1 AS 
            ( SELECT xmlData FROM dual )
            SELECT 
                    cell.cell_ordinal cell_ordinal , 
                 cell.cell_ordinal_value cell_ordinal_value 
                    FROM  table1, 
                        XMLTABLE (
                            xmlnamespaces
                            ( default 'urn:schemas-microsoft-com:xml-analysis:mddataset',
                            'http://schemas.xmlsoap.org/soap/envelope/' as "SOAP-ENV",
                            'urn:schemas-microsoft-com:xml-analysis' as "m",
                            'http://www.w3.org/2001/XMLSchema-instance' as "xsi",
                            'http://www.w3.org/2001/XMLSchema' as "xsd"
                            ),      
                            '/SOAP-ENV:Envelope/SOAP-ENV:Body/m:ExecuteResponse/m:return/root/CellData/Cell'
                            PASSING xmlData
                            COLUMNS Cell_Ordinal VARCHAR2(80) PATH '@CellOrdinal',
                                    cell_ordinal_value VARCHAR2(80) PATH 'Value' 
                        ) Cell 
                )
		LOOP
			ordRecT.cell_ordinal := rec.cell_ordinal;
			ordRecT.cell_ordinal_value := rec.cell_ordinal_value;
			PIPE ROW( ordRecT);
		END LOOP;
        
	END extractValueInfoFromXML;
    
END XMLA_MDX;