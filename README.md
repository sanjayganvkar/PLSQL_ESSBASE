# PLSQL_ESSBASE

The attached PL/SQL package demonstrates the way to extract Essbase data from Oracle PL/SQL via the APS services and Oracle provided XML parsing package.

The SQL interface allows the Oracle PL/SQL based applications to directly extract data from Essbase with the presentation done in a relational format, which can be subsequently used in the SQL Queries.

The interface should be used to extract critical summary data and not as a mechanism to move complete cube data to Oracle. In those
scenarios, the usual Essbase Export should be used to transport the data.
