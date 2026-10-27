import redshift_connector


conn = redshift_connector.connect(
     host='bpei-iris.692859911099.us-east-1.redshift-serverless.amazonaws.com',
     database='dev',
     port=5439,
     user='lxp1655',
     password='!Harianant0587!'
  )


cursor = conn.cursor()

# Query a table using the Cursor
cursor.execute("select * from may_2026.iris_registry_data_ccl_filtered_05_2026.patient_refraction limit 100 ")
                
#Retrieve the query result set
result: tuple = cursor.fetchall()
print(result)
