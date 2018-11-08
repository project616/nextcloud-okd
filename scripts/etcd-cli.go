package main

import (
	"context"
	"encoding/json"
	"fmt"
	"github.com/coreos/etcd/client"
	"gopkg.in/ini.v1"
	"io/ioutil"
	"log"
	"net/http"
	_ "reflect"
	"strconv"
	"time"
)

type Nextcloud struct {
	Base          map[string]string
	S3            map[string]string
	Mariadb       map[string]string
	Etcd_endpoint string
	Etcd_root     string
}

/**
* leaf represents the (key,value)
**/
type SectNode struct {
	leaf map[string]string
	next []*SectNode
}

type Etcd struct {
	endpoint string
	cfg      client.Config
	caller   client.KeysAPI
}

func (et *Etcd) health() (bool, error) {

	resp, err := http.Get(et.endpoint + "/health")
	log.Println("[ETCD] Calling endpoint", (et.endpoint + "/health"))

	if err != nil {
		log.Fatal(err)
	}

	body, readErr := ioutil.ReadAll(resp.Body)
	if readErr != nil {
		log.Fatal(readErr)
	}

	var s map[string]interface{}

	if err := json.Unmarshal(body, &s); err != nil {
		log.Fatal(err)
	}

	return strconv.ParseBool(s["health"].(string))
}

func build_k(cfg *ini.File, root *SectNode, section string) SectNode {
	keys := cfg.Section(section).KeyStrings()
	var mymap = make(map[string]string)

	for _, key := range keys {
		mymap[string(key)] = cfg.Section(section).Key(key).String()
	}

	n := SectNode{mymap, nil}
	root.next = append(root.next, &n)

	return n
}

func build_keys(cfg *ini.File, section string) map[string]string {
	keys := cfg.Section(section).KeyStrings()
	var mymap = make(map[string]string)

	for _, key := range keys {
		mymap[string(key)] = cfg.Section(section).Key(key).String()
	}
	return mymap
}

func conf_load(fname string) Nextcloud {
	cfg, err := ini.InsensitiveLoad(fname)

	if err != nil {
		log.Fatal(err)
	}

	nx := Nextcloud{}
	for _, section := range cfg.SectionStrings() {
		switch section {
		case "default":
			log.Print("[INI] GOT SECTION ", string(section))
			nx.Base = build_keys(cfg, string(section))
			log.Print("[INI:basemap]", nx.Base)
		case "s3":
			log.Print("[INI] GOT SECTION ", string(section))
			nx.S3 = build_keys(cfg, string(section))
			log.Print("[INI:s3map]", nx.S3)
		case "etcd":
			log.Print("[INI] GOT SECTION ", string(section))
			nx.Etcd_endpoint = build_keys(cfg, string(section))["endpoint"]
			log.Print("[INI:etcd]", nx.Etcd_endpoint)
		case "mariadb":
			log.Print("[INI] GOT SECTION ", string(section))
			nx.Mariadb = build_keys(cfg, string(section))
			log.Print("[INI:mariadb]", nx.Mariadb)
		default:
			log.Print("[INI] SECTION ", string(section), " => [NOT ALLOWED]")
		}
	}
	nx.Etcd_root = "nextcloud"
	return nx
}

func init_etcd(ep string) Etcd {

	cfg := client.Config{
		Endpoints:               []string{ep},
		Transport:               client.DefaultTransport,
		HeaderTimeoutPerRequest: time.Second,
	}

	c, err := client.New(cfg)

	if err != nil {
		log.Fatal(err)
	}

	caller := client.NewKeysAPI(c)

	et := Etcd{ep, cfg, caller}

	return et
}

func (et *Etcd) set_value(key string, value string) bool {

	log.Print("[ETCD:Set-1] Setting ", key, " with ", value, " value")

	resp, err := et.caller.Set(context.Background(), key, value, nil)

	if err != nil {
		log.Fatal(err)
	} else {
		// print common key info
		log.Printf("[ETCD:Set-2] Set is done. Metadata is %q\n", resp)
		return true
	}
	return false
}

func (et *Etcd) get_value(key string) string {

	log.Print("[ETCD:Get-1] Getting value for ", key)

	resp, err := et.caller.Get(context.Background(), key, nil)

	if err != nil {
		log.Fatal(err)
	} else {
		// print key/value info
		log.Printf("[ETCD:Get-2] %q key has %q value\n", resp.Node.Key, resp.Node.Value)
		return resp.Node.Value
	}
	return "err"
}

func (x *Nextcloud) register_base_values(et Etcd) {

	/*

		v := reflect.ValueOf(*x)

		values := make([]interface{}, v.NumField())

		for i := 0; i < v.NumField(); i++ {
			values[i] = v.Field(i).Interface()
		}
		fmt.Println(values)

		for j := 0; j < len(values); j++ {
			val := values[j]
				for key, value := range val.(map[string]string) {
					fmt.Println("[ETCD] Registering [", key, "-", value, "]")
					//et.set_value(et, (nx.Etcd_root + \"/" + key), value)
				}
			}
		}
	*/

	//Register base values
	for key, value := range x.Base {
		et.set_value((x.Etcd_root + "/" + key), value)
		fmt.Println("[ETCD] Registering [", key, "-", value, "] on", x.Etcd_root)
	}
}

func (x *Nextcloud) register_s3values(et Etcd) {
	for key, value := range x.S3 {
		et.set_value((x.Etcd_root + "/s3/" + key), value)
		fmt.Println("[ETCD] Registering [", key, "-", value, "] on ", x.Etcd_root+"/s3")
	}
}

func (x *Nextcloud) register_db_values(et Etcd) {
	for k, v := range x.Mariadb {
		et.set_value((x.Etcd_root + "/mariadb/" + k), v)
		fmt.Println("[ETCD] Registering [", k, "-", v, "] on ", x.Etcd_root+"/mariadb")
	}

}

func main() {
	fmt.Println("[ETCD] Yet another client to interact with etcd API")

	nx := conf_load("nextcloudrc")
	var et = init_etcd(nx.Etcd_endpoint)

	//Test: checking health
	h, _ := et.health()
	log.Println("[ETCD] health => ", h)

	nx.register_base_values(et)
	nx.register_s3values(et)
	nx.register_db_values(et)
}
