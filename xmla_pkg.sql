create or replace PACKAGE                XMLA_MDX
AS

/*****************************************************************************************
Package : Extracts the Essbase data via XMLA services and presents in a Relational Table Format. A portion of this package 
          ( getXmlaData function ) is based on Evgeniy.Rasyuks essbase-plsql-interface package.
			 The internal functions have been deliberately exposed in the headers to give an insight of the transformation process

Usage Example 
************************
  
  WITH
    table1 AS
    (
        SELECT
            XMLA_MDX.getMDXData( p_mdx_query =>
            'SELECT NON EMPTY  
						{ Children([Product]) }   ON AXIS(0),
						{ Children([Measures]) }  ON AXIS(1)  ,
						{ Children([Year]) }  ON AXIS(2)  ,
						{ Children([Market]) }  ON AXIS(3)                       
				  FROM [Sample].[Basic]',				
				p_aps_url =>'http://foobar:19000/aps/XMLA',
            p_essbase_server => 'foobar.com', 
				p_essbase_user => 'yyyyy',
            p_essbase_password =>'xxxxx',
				p_suppress_missing => 'Y') xmlData
        FROM
            DUAL
    )
			SELECT
				 dt.Product, dt.Measures, dt.Year, dt.Market,  dt.CELLVALUE
			FROM
				 table1, XMLTABLE ('/TABLE/REC' PASSING xmlData 
												COLUMNS Product VARCHAR2(80) PATH 'Product', 
														  Measures VARCHAR2(80) PATH 'Measures',
														  Year VARCHAR2(80) PATH 'Year',
														  Market VARCHAR2(80) PATH 'Market',
														  CELLVALUE NUMBER PATH 'CELLVALUE'
										) dt
			;	 
*********************************************************************************/
	-- Entry Point
	FUNCTION getMDXData(
					 p_mdx_query VARCHAR2,
					 p_aps_url VARCHAR2,
					 p_essbase_server VARCHAR2,
					 p_essbase_user VARCHAR2,
					 p_essbase_password VARCHAR2,
					 p_suppress_missing VARCHAR2 DEFAULT 'N'
				) RETURN XMLTYPE ;
						  
     -- XMLA Call to return MDX data in XML Format               
	TYPE dimRecType IS RECORD
	(
		Axist varchar2(80),
		Ordinal varchar2(80),
		dimension varchar2(80),
		DimName varchar2(80)
	);
	TYPE dimRecTab IS TABLE of dimRecType ;
         
	TYPE cell_ord_rec_type IS RECORD
	(
            cell_ordinal VARCHAR2(80),
            cell_ordinal_value VARCHAR2(80)
	);
	TYPE cell_ord_tab IS TABLE of cell_ord_rec_type ;
     
	FUNCTION extractDimInfoFromXML ( xmlData IN XMLTYPE )  RETURN dimRecTab PIPELINED;
	FUNCTION extractValueInfoFromXML ( xmlData IN XMLTYPE ) RETURN cell_ord_tab PIPELINED;	  
	
   FUNCTION get_xmla_request_string ( p_mdx_query IN VARCHAR2, p_essbase_server IN VARCHAR2) RETURN VARCHAR2;
 
	FUNCTION extract_xml_to_string (  xmlData in XMLTYPE ,p_suppress_missing IN  VARCHAR2) RETURN CLOB;
	FUNCTION getXmlaData( p_mdx_query VARCHAR2, p_aps_url VARCHAR2, p_essbase_server VARCHAR2, p_essbase_user VARCHAR2, 
				p_essbase_password VARCHAR2) RETURN XMLTYPE ;
	FUNCTION translate_meta_chars(p_str  VARCHAR2) RETURN VARCHAR2;
	
END XMLA_MDX;