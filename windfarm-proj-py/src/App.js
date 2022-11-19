import logo from "./logo.svg";
import "./App.css";
import Button from "@mui/material/Button";
import { ethers } from "ethers";
import { useState, useEffect } from "react";
import Dashboard from "./DashComponent/Dashboard";
import { Web3ReactProvider } from "@web3-react/core";
import { Web3Provider } from "@ethersproject/providers";

function App() {
  const getLibrary = (provider) => {
    return new Web3Provider(provider);
  };

  return (
    <Web3ReactProvider getLibrary={getLibrary}>
      <div className="App">
        <Dashboard />
      </div>
    </Web3ReactProvider>
  );
}

export default App;
