import * as React from "react";
import Avatar from "@mui/material/Avatar";
import Button from "@mui/material/Button";
import CssBaseline from "@mui/material/CssBaseline";
import TextField from "@mui/material/TextField";
import FormControlLabel from "@mui/material/FormControlLabel";
import Checkbox from "@mui/material/Checkbox";
import Link from "@mui/material/Link";
import Grid from "@mui/material/Grid";
import Box from "@mui/material/Box";
import LockOutlinedIcon from "@mui/icons-material/LockOutlined";
import Typography from "@mui/material/Typography";
import Container from "@mui/material/Container";
import { createTheme, ThemeProvider } from "@mui/material/styles";
import { ethers } from "ethers";
import { useWeb3React } from "@web3-react/core";
import { InjectedConnector } from "@web3-react/injected-connector";
import deployerABI from "../deployerABI.json";
import policyABI from "../policyABI.json";

function Copyright(props) {
  return (
    <Typography
      variant="body2"
      color="text.secondary"
      align="center"
      {...props}
    >
      {"Copyright © "}
      <Link color="inherit" href="https://test.aquila.finance/">
        Aquila Finance
      </Link>{" "}
      {new Date().getFullYear()}
      {"."}
    </Typography>
  );
}

const theme = createTheme();
//const walletz0rs = new InjectedConnector();
const POLICY_AMOUNT = ethers.utils.parseEther("0.03");
const POLICY_DURATION = 3;
const LINK_TOKEN_ADDRESS = "0x326C977E6efc84E512bB9C30f76E30c160eD06FB";
const ACCUWEATHER_ORACLE = "0xB9756312523826A566e222a34793E414A81c88E1";
const LOCATION_LATITUDE = "49.703168";
const LOCATION_LONGITUDE = "-125.630035";
let newPolicyContract;

export default function NewPolicy() {
  //  const handleSubmit = (event) => {
  //    event.preventDefault();
  //    const data = new FormData(event.currentTarget);
  //    console.log({
  //      email: data.get("email"),
  //      password: data.get("password"),
  //    });
  //  };

  const { activate, active, library: provider } = useWeb3React();
  async function newWindFarm() {
    if (active) {
      const signer = provider.getSigner();
      const deployer = "0x06cBB83E7c54780DD5DCE6742256A3E1b5A70907";
      const contractAddress = "0x603346539c3E2c41D7EC37e7e6c1D5175Ab76AC3";
      const deployerContract = new ethers.Contract(
        contractAddress,
        deployerABI,
        deployer
      );

      const tx = await deployerContract.newWindFarm(
        LINK_TOKEN_ADDRESS,
        ACCUWEATHER_ORACLE,
        POLICY_AMOUNT,
        signer,
        POLICY_DURATION,
        LOCATION_LATITUDE,
        LOCATION_LONGITUDE
      );

      tx.wait(1);
      const deployedPolicies = deployerContract.getDeployedPolicies();
      deployedPolicies.wait(1);
      const newFarmAddress = deployedPolicies.slice(-1);
      const newPolicyContract = new ethers.Contract(
        newFarmAddress,
        policyABI,
        signer
      );
    }
  }

  return (
    <ThemeProvider theme={theme}>
      <Container component="main" maxWidth="xs">
        <CssBaseline />
        <Box
          sx={{
            marginTop: 8,
            display: "flex",
            flexDirection: "column",
            alignItems: "center",
          }}
        >
          <Avatar sx={{ m: 1, bgcolor: "secondary.main" }}>
            <LockOutlinedIcon />
          </Avatar>
          <Typography component="h1" variant="h5">
            Create New DeSurance Policy
          </Typography>
          <Box component="form" noValidate sx={{ mt: 3 }}>
            <Grid container spacing={2}>
              <Grid item xs={12} sm={6}>
                <TextField
                  name="latitude"
                  required
                  fullWidth
                  id="latitude"
                  label="Latitude"
                  autoFocus
                />
              </Grid>
              <Grid item xs={12} sm={6}>
                <TextField
                  required
                  fullWidth
                  id="longitude"
                  label="Longitude"
                  name="longitude"
                />
              </Grid>
              <Grid item xs={12}>
                <TextField
                  required
                  fullWidth
                  id="duration"
                  label="Duration of Policy"
                  name="duration"
                />
              </Grid>
              <Grid item xs={12}>
                <TextField
                  required
                  fullWidth
                  name="turbinemanufacturer"
                  label="Turbine Manufacturer"
                  id="turbinemanufacturer"
                />
              </Grid>
              <Grid item xs={12}>
                <TextField
                  required
                  fullWidth
                  name="AgeofTurbines"
                  label="Age of Turbines"
                  id="AgeofTurbines"
                />
              </Grid>
              <Grid item xs={12}>
                <FormControlLabel
                  control={
                    <Checkbox value="iceProtectionSystem" color="primary" />
                  }
                  label="Ice Protection System (IPS)?"
                />
                <FormControlLabel
                  control={
                    <Checkbox value="fireSuppressionSystem" color="error" />
                  }
                  label="Fire Suppression?"
                />
              </Grid>
            </Grid>
            <Button
              type="submit"
              fullWidth
              color="success"
              variant="contained"
              sx={{ mt: 3, mb: 2 }}
            >
              Take Up New Wind Farm Policy
            </Button>
          </Box>
        </Box>
        <Copyright sx={{ mt: 0 }} />
      </Container>
    </ThemeProvider>
  );
}
