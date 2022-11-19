import * as React from "react";
import Link from "@mui/material/Link";
import Typography from "@mui/material/Typography";
import Title from "./Title";
import { Button } from "@mui/material";

export default function Deposits() {
  return (
    <React.Fragment>
      <Title>Latest Wind Speed</Title>
      <Typography component="p" variant="h4">
        17 km/h
      </Typography>
      <Typography color="text.secondary" sx={{ flex: 1 }}>
        Updated every 5 min
      </Typography>
      <div>
        <Button variant="contained" color="primary">
          Pay Premium
        </Button>
      </div>
    </React.Fragment>
  );
}
