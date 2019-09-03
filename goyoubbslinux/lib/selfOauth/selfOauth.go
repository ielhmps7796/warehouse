package selfOauth

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"fmt"
	"html/template"
	"io/ioutil"
	"net/http"
	"strconv"
	"time"

	"github.com/httprouter"
	"golang.org/x/oauth2"
	"golang.org/x/randx"
)


type urlstr struct {
	URL string
}

type ed struct {
	Name        string
	Description string
	Hint        string
	Debug       string
}

type UserInfo struct {
	Sid string `json:"sid"`
	Sub string `json:"sub"`
}

func NewSelfOauth(ClientID, clientSecret string) (*UserInfo, error) {
	ctx := context.Background()
	ctx = context.WithValue(context.Background(), oauth2.HTTPClient, &http.Client{Transport: &http.Transport{
		TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
	}})

	conf := oauth2.Config{
		ClientID:     ClientID,
		ClientSecret: clientSecret,
		Endpoint: oauth2.Endpoint{
			//TokenURL: "https://ory-hydra-example--hydra:4444/oauth2/token",
			TokenURL: "https://192.168.31.106:9000/oauth2/token",
			AuthURL:  "https://192.168.31.106:9000/oauth2/auth",
		},
		RedirectURL: "http://127.0.0.1:8082/callback",
		Scopes:      []string{"openid", "offline", "photos.read"},
	}

	state, err := randx.RuneSequence(24, randx.AlphaLower)
	if err != nil {
		fmt.Println(err)
	}
	nonce, err := randx.RuneSequence(24, randx.AlphaLower)
	if err != nil {
		fmt.Println(err)
	}

	authCodeURL := conf.AuthCodeURL(
		string(state),
		oauth2.SetAuthURLParam("audience", ""),
		oauth2.SetAuthURLParam("nonce", string(nonce)),
		oauth2.SetAuthURLParam("prompt", ""),
		oauth2.SetAuthURLParam("max_age", strconv.Itoa(0)),
	)

	r := httprouter.New()
	var tlsc *tls.Config
	server := &http.Server{Addr: ":9010", Handler: r, TLSConfig: tlsc}

	var shutdown = func() {
		time.Sleep(time.Second * 1)
		ctx, cancel := context.WithTimeout(context.Background(), time.Second*5)
		defer cancel()
		_ = server.Shutdown(ctx)
	}

	r.GET("/", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		t, _ := template.ParseFiles("E:/GoWorks/src/test2/views/login.html")
		t.Execute(w, &struct{ URL string }{URL: authCodeURL})
	})

	r.GET("/callback", func(w http.ResponseWriter, r *http.Request, _ httprouter.Params) {
		if len(r.URL.Query().Get("error")) > 0 {
			fmt.Printf("Got error: %s\n", r.URL.Query().Get("error_description"))

			w.WriteHeader(http.StatusInternalServerError)
			_ = tokenUserError.Execute(w, &ed{
				Name:        r.URL.Query().Get("error"),
				Description: r.URL.Query().Get("error_description"),
				Hint:        r.URL.Query().Get("error_hint"),
				Debug:       r.URL.Query().Get("error_debug"),
			})

			go shutdown()
			return
		}

		if r.URL.Query().Get("state") != string(state) {
			fmt.Printf("States do not match. Expected %s, got %s\n", string(state), r.URL.Query().Get("state"))

			w.WriteHeader(http.StatusInternalServerError)
			_ = tokenUserError.Execute(w, &ed{
				Name:        "States do not match",
				Description: "Expected state " + string(state) + " but got " + r.URL.Query().Get("state"),
			})
			go shutdown()
			return
		}

		code := r.URL.Query().Get("code")
		token, err := conf.Exchange(ctx, code)
		if err != nil {
			fmt.Printf("Unable to exchange code for token: %s\n", err)

			w.WriteHeader(http.StatusInternalServerError)
			_ = tokenUserError.Execute(w, &ed{
				Name: err.Error(),
			})
			go shutdown()
			return
		}

		idt := token.Extra("id_token")
		fmt.Printf("Access Token:\n\t%s\n", token.AccessToken)
		fmt.Printf("Refresh Token:\n\t%s\n", token.RefreshToken)
		fmt.Printf("Expires in:\n\t%s\n", token.Expiry.Format(time.RFC1123))
		fmt.Printf("ID Token:\n\t%v\n\n", idt)

		/*_ = tokenUserResult.Execute(w, struct {
			AccessToken  string
			RefreshToken string
			Expiry       string
			IDToken      string
			//	Name 		 string
		}{
			AccessToken:  token.AccessToken,
			RefreshToken: token.RefreshToken,
			Expiry:       fmt.Sprintf("%s", token.Expiry.Format(time.RFC1123)),
			IDToken:      fmt.Sprintf("%v", idt),
		})*/

		headers := map[string][]string{
			"Accept":        []string{"application/json"},
			"Authorization": []string{"Bearer " + token.AccessToken},
		}

		//var body []byte
		//body = nil
		tr := &http.Transport{
			TLSClientConfig: &tls.Config{InsecureSkipVerify: true},
		}

		req, err := http.NewRequest("GET", "https://192.168.31.106:9000/userinfo", nil)
		if err != nil {
			fmt.Println("**" + err.Error())
		}
		req.Header = headers
		client := &http.Client{Transport: tr}
		resp, err := client.Do(req)
		if err != nil {
			fmt.Println("***" + err.Error())
		}
		defer resp.Body.Close()
		contents, err := ioutil.ReadAll(resp.Body)
		if err != nil {
			fmt.Println("****" + err.Error())
		}
		//fmt.Printf("Content: %s\n", contents)
		var structcontent content
		json.Unmarshal([]byte(contents), &structcontent)
		fmt.Println(structcontent.Sub)

	})

	server.ListenAndServe()
}
