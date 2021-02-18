import json 
import os
import base64
import requests
import struct
import binascii
import sys
import yaml

class PyBimServer():

    def __init__(self,host,port,userName,password, setup = False):
        self.host = host

        self.port = str(port)
        
        self.userName = userName
        
        self.password = password

        self.bimServer_address = "http://"+self.host+":"+ self.port + "/BIMserver"

        self.json_api_adress = self.bimServer_address + "/json"

        self.token = None

        if(setup):
            self.setupServer()

        self.token = self.login()

    def send_json_request(self,file,parameters = None):
        with open(os.path.dirname(os.path.abspath(__file__))+"/json_requests/" + file) as f:
            request = json.load(f)
        if(self.token):
            request['token'] = self.token
        if(parameters):
            for parameterName, parameterValue in parameters.items() :
                request['request']['parameters'][parameterName] = parameterValue
        response = requests.post(self.json_api_adress, json = request)
        response_as_json = response.json()
        if(response_as_json['response']['result']):    
            return response_as_json['response']['result']

    def send_json_requests(self,rqsts):
        with open(os.path.dirname(os.path.abspath(__file__))+'/json_requests/multiple_requests.json') as f:
            request = json.load(f)
        if(self.token):
            request['token'] = self.token
        request['requests'] = rqsts
        requests.post(self.json_api_adress, json = request).json()

    def setupServer(self):
        print("setup parameters")
        parameters = {"siteAddress" : self.bimServer_address,
                        "adminName" : self.userName,
                        "adminUsername" : self.userName,
                        "adminPassword" : self.password }
        self.send_json_request('setup.json',parameters)

    def login(self):
        parameters = {"username" : self.userName,
                        "password" : self.password }
        return self.send_json_request('login.json',parameters)

    def getRequestExtendedDataSchema(self,extendedDataSchema):
        with open(os.path.dirname(os.path.abspath(__file__))+'/json_requests/addExtendedDataSchema.json') as f:
            request = json.load(f)
        request['parameters']['extendedDataSchema'] = extendedDataSchema
        return request

    def addAllExtendedDataSchemas(self):
        allExtendedDataSchemas = self.send_json_request('getAllExtendedDataSchemas.json')
        rqsts = []
        for extendedDataSchema in allExtendedDataSchemas :
            rqsts.append(self.getRequestExtendedDataSchema(extendedDataSchema))
        self.send_json_requests(rqsts)


    def installPlugin(self,pluginId) :
        parameters = {"artifactId": pluginId}
        pluginBundle = self.send_json_request("getPluginBundle.json",parameters)
        pluginVersion = pluginBundle['latestVersion']['version'] 
        parameters.update({"version": pluginVersion})    

        pluginInformations = self.send_json_request("getPluginInformation.json"
                                                        ,parameters)
        for pluginInformation in pluginInformations :
            pluginInformation["installForAllUsers"] = True
            pluginInformation["installForNewUsers"] = True  
        parameters.update({"plugins":pluginInformations}) 

        self.send_json_request("installPluginBundle.json",parameters)


    def installAllPlugins(self):
        print("IntallingPlugins")
        
        print("Installing BimViews ...")
        
        self.installPlugin("bimviews")
        
        print("Bimviews installed !")
        
        print("Installing bimsurfer3 ...")
        
        self.installPlugin("bimsurfer3")
        
        print("bimsurfer3 installed !")
        
        print("Installing ifcOpenShellPlugin ...")
        
        self.installPlugin("ifcopenshellplugin")
        print("ifcOpenShellPlugin installed !")
        
        print("Installing IfcPlugins ...")
        
        self.installPlugin("ifcplugins")
        print("IfcPlugins installed !")

        print("Installing binaryserializers ...")
        
        self.installPlugin("binaryserializers")
        
        print("binaryserializers installed !")
        
        print("Installing console ...")
        
        self.installPlugin("console")
        
        print("Console installed !")
        
        print("Installing gltf ...")
        
        self.installPlugin("gltf")
        print("gltf installed !")

        print("Installing mergers ...")
        
        self.installPlugin("mergers")

        print("mergers installed !")


    def uploadFile(self,fileName,deserializerOid,poid,topicId) :
        with open(fileName,'rb') as f:
                ifc_data = f.read()
        self.send_json_request("uploadFile.json", { 
            "poid": poid,
            "comment": fileName,
            "deserializerOid": deserializerOid,
            "fileName": fileName,
            "fileSize": len(ifc_data),
            "data": base64.b64encode(ifc_data).decode('utf-8')
            })

    def checkinFile(self,fileName, projectName, typeSchema = "ifc4") :
        parameters = {"schema": typeSchema, "projectName" : projectName}
        projectDetail = self.send_json_request("addProject.json",parameters)
        poid = projectDetail['oid']
        
        deserializerDetail = self.send_json_request("getSuggestedDeserializerForExtension.json", 
                                                        {"extension" : "ifc", "poid" : poid})
        deserializerOid = deserializerDetail["oid"]
        self.uploadFile(fileName,deserializerOid,poid,5)
        
    def getRoidByProjectName(self,projectName) :
        project_detail = self.send_json_request("getProjectsByName.json",
                                                    {"name" : projectName})
        self.roid = project_detail[0]["lastRevisionId"]

    def getGeometryInfo(self,oid) :
        return self.send_json_request("getGeometryInfo.json",
                                        {"roid" : self.roid, "oid": oid})

    def getDataObjectByOid(self,oid) : 
        return self.send_json_request("getDataObjectByOid.json",
                                        {"roid" : self.roid, "oid": oid})

    def getRevisionSummary(self) :
        return self.send_json_request("getRevisionSummary.json",{"roid": self.roid})                    

    def getGeometryData(self,oid) :
        geometryInfo = self.getGeometryInfo(oid)
        dataId = geometryInfo["dataId"]
        geometryData = self.getDataObjectByOid(dataId)
        for value in geometryData["values"] :
            if(value["fieldName"] == "indices") :
                oidIndicesBuffer = value["oid"]
            if(value["fieldName"] == "vertices") :
                oidVerticesBuffer = value["oid"]
        
        if oidIndicesBuffer and oidVerticesBuffer :
            indicesBuffer = self.getIndicesBuffer(oidIndicesBuffer)
            verticesBuffer = self.getVerticesBuffer(oidVerticesBuffer)
            print(oidIndicesBuffer)

    def getSerializer(self,pluginClassName) :
        return self.send_json_request("getSerializer.json", {"pluginClassName": pluginClassName})


    def download(self, query, serializerOid) :
        topicId = self.send_json_request("download.json",{"roids": [self.roid],"query":query,"serializerOid" : serializerOid})
        result = self.send_json_request("getDownloadData.json",{"topicId" : topicId})
        test = base64.b64decode(result["file"]).decode("utf-8") 
        test_json = json.loads(test) 
        return test_json["objects"]

    def queryByEntity(self,entityName):
        return "{\"queries\":[{\"type\":\""+ entityName +"\"}]}"

    def getAllOidByEntity(self) :
        summary = self.getRevisionSummary()
        entities = summary["list"][0]
        serializerOid = self.getSerializer("org.bimserver.serializers.JsonStreamingSerializerPlugin")["oid"]
        entityOidDict = dict()
        for entity in entities["types"] :
            query = self.queryByEntity(entity["name"])
            entityOidDict[entity["name"]] = self.download(query,serializerOid)
        
        return entityOidDict
        


    def getIndicesBuffer(self,oid) :
        response = self.getDataObjectByOid(oid)
        data = response['values'][0]['stringValue']
        arr = bytes(data, 'utf-8') 
        test = base64.b64decode(arr) 
        iterator = struct.iter_unpack('<i',test)
        indices = []
        for temp in iterator :
            indices.append(temp[0])
        return indices

    def getVerticesBuffer(self,oid) :
        response = self.getDataObjectByOid(oid)
        data = response['values'][0]['stringValue']
        arr = bytes(data, 'utf-8')
        test = base64.b64decode(arr) 
        iterator = struct.iter_unpack('<d',test)
        vertices = []
        for temp in iterator :
            vertices.append(temp[0])
        return vertices



def init_from_config_file(bimServer_config_file_path,setup = False):
    with open(bimServer_config_file_path, 'r') as bs_config_file:
        try:
            bs_config = yaml.load(bs_config_file, Loader=yaml.FullLoader)
            bs_config_file.close()
        except:
            print('ERROR: ', sys.exc_info()[0])
            bs_config_file.close()
            sys.exit()
    
    if (("BS_HOST" not in bs_config) 
            or ("BS_USER" not in bs_config)
            or ("BS_PORT" not in bs_config)
            or ("BS_PASSWORD" not in bs_config)):
        print("ERROR: BimServer is not properly defined in " + 
                 bimServer_config_file_path + 
                 ", please refer to README.md")
        sys.exit()
    return PyBimServer(bs_config["BS_HOST"],bs_config["BS_PORT"],bs_config["BS_USER"],bs_config["BS_PASSWORD"],setup)
